
// Counts occurrences of each character to handle indistinguishable objects
function getCharacterCounts(str) {
    const counts = {};
    for (const char of str) {
        counts[char] = (counts[char] || 0) + 1; }
    return counts;
}



// Independent controller for an individual database value
function processValueSeparately(rawCoordStr, min, max) {
    if (!rawCoordStr) return "0.000000";
    const cleanedStr = rawCoordStr.trim();

    // 1. Separate the structural symbols from the actual numeric digits
    const digitsOnly = cleanedStr.replace(/[^0-9]/g, "");
    const charCounts = getCharacterCounts(digitsOnly);

    let attempts = 0;
    while (attempts < 500) {
        let currentString = "";
        const pool = { ...charCounts };
        let digitIndex = 0;

     // 2. Shuffle the digits using an algorithm based on Permutation with Indistinguishable Object using a pool obtained from "counts"
        const shuffledDigitsArray = [];
        while (shuffledDigitsArray.length < digitsOnly.length) {

        const availableChoices = Object.keys(pool).filter(char => pool[char] > 0);
        if (availableChoices.length === 0) break;
         const randomChar = availableChoices[Math.floor(Math.random() * availableChoices.length)];
            shuffledDigitsArray.push(randomChar);
            pool[randomChar]--; }
    
    

         // 3. Rebuild the final string by mirroring the original structure exactly
        for (let i = 0; i < cleanedStr.length; i++) {
            const originalChar = cleanedStr[i];
            if (originalChar === "-" || originalChar === ".") {
                currentString += originalChar; // Keep symbols locked in place
            } else {
                currentString += shuffledDigitsArray[digitIndex]; // Drop shuffled digit here
                digitIndex++;
            }
        }

         // 4. Validate boundaries using core structural logic
        const value = parseFloat(currentString);
        if (!isNaN(value) && value >= min && value <= max) {
            return value.toFixed(6);
        }        
        attempts++;    
    }        
// Fallback if no valid unique variation passes within 500 attempts    
return parseFloat(cleanedStr).toFixed(6);}



// Helper function to check if the complete TRIPLET already exists in SQL
async function isTripletRegistered(lat, long, alt) {
    try {
        const response = await fetch("http://localhost:8080/check-duplicate-triplet", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ lat, long, alt })
        });
        const data = await response.json();
        return data.isRegistered; 
    } catch (error) {
        console.error("Verification server network error:", error);
        return false; 
    }
}

// CORE INTERACTION FUNCTION
async function handleScramble(event) {
    // Intercept standard browser submission reloads
    if (event) event.preventDefault();

    //Function to govern display cards
    const statusEl = document.getElementById("statusMessage");
const cardEl = document.getElementById("resultCard");

function showStatus(text, className) {
    cardEl.className = "card-result"; 
    statusEl.innerText = text;
    statusEl.className = `status-msg active ${className}`;
}

function displayFinalCard(title, typeClass, addr, lat, long, alt) {
    statusEl.className = "status-msg"; 
    document.getElementById("cardTitle").innerText = title;
    document.getElementById("outAddress").innerText = addr;
    document.getElementById("outLat").innerText = lat;
    document.getElementById("outLong").innerText = long;
    document.getElementById("outAlt").innerText = alt;
    cardEl.className = `card-result visible ${typeClass}`;
}

    // Leverages top external CSS helper function for states
    showStatus("Initializing Database Query...", "status-loading");

    const addressInput = document.getElementById("address");
    if (!addressInput) {
        alert("Error: HTML elements could not be detected by JavaScript.");
        return;
    }
    
    const inputAddress = addressInput.value.trim();
    if (!inputAddress) {
        showStatus("Please enter an address first.", "status-warning");
        return;
    }

    try {
        // Retrieve base matching layout columns via PowerShell REST Listener
        const response = await fetch("http://localhost:8080/get-private-coordinates", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ address: inputAddress })
        });

        const data = await response.json();

        if (data.status === "success") {
            let scrambledLat, scrambledLong, scrambledAlt;
            let isDuplicate = true;
            let loopGuard = 0;

            showStatus("Processing indistinguishable permutations...", "status-processing");

            // Loop until a brand new, completely unregistered combination triplet is found
            while (isDuplicate && loopGuard < 350) {
                scrambledLat = processValueSeparately(data.lat, -90, 90);
                scrambledLong = processValueSeparately(data.long, -180, 180);
                scrambledAlt = processValueSeparately(data.alt, -430, 9000); 

                isDuplicate = await isTripletRegistered(scrambledLat, scrambledLong, scrambledAlt);
                loopGuard++;
            }

            // Pipes variables strictly to permanent HTML template elements via top helper
            displayFinalCard("Unique Triplet Generated Successfully", "card-private", inputAddress, scrambledLat, scrambledLong, scrambledAlt);
            
        } else if (data.status === "not_found") {
            showStatus("Address not found in SQL database.", "status-error");
        } else {
            showStatus(`DB Error: ${data.message}`, "status-error");
        }
    } catch (error) {
        console.error("Fetch Connection Fault Error Details:", error);
        showStatus("Backend Connection Error. Could not connect to API server.", "status-error");
    }
}
