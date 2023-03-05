local htmlparser = loadstring(game:HttpGet("https://raw.githubusercontent.com/Testerboy21/lua-htmlparser/master/src/htmlparser.lua"))()
local validTypes = {"Titanic", "Huge", "Shiny", "Exclusive"}

if table.find(validTypes, petType) then
    local toConcat, url, rootType;

    if petType == validTypes[2] or petType == validTypes[4] then
        toConcat = "s"

        if petType == validTypes[2] then
            rootType = "</p>"
        else
            rootType = "</code>"
        end
    else
        toConcat = "-pets"
        rootType = "[style='text-align:center;white-space:pre-wrap;']"
    end

    url = petType:lower() .. toConcat

    local response = syn.request(
        {
            Url = string.format("https://petsimulatorvalues.com/%s/", url),
            Method = "GET"
        }
    )

    local body = response.Body 
    local root = htmlparser.parse(body, math.huge)
    local text = root:select(rootType)

    local function filter_values()
        local function should_filter(index, content)
            local typeOf = petType

            if petType == validTypes[4] then -- No special keyword for exclusives, so filter out any values and grab name
                if not (content:match("-") or content:match(":") or content:match("Point")) then
                    typeOf = content
                end
            end

            local wanted = {typeOf, "Gem Value", "Demand"}
            local badChunk, badLine, tempContent;

            local found = string.find(content, "N/A") or string.find(content, "SOON")

            if string.find(content, wanted[2]) then -- For exclusives with no gem value
                hasGemValue = true
            end

            for i2, v2 in pairs(wanted) do
                if string.find(content, v2) then
                    tempContent = content -- because array might not be done looping, so compare previous index
                    badLine = false

                    if found or (string.find(content, "Demand") and not hasGemValue) then -- demand comes after gem value, so check
                        badChunk = true
                        hasGemValue = false
                    end
                else
                    if content ~= tempContent or found then
                        badLine = true
                    end
                end
            end

            return badChunk, badLine
        end

        local filter, filterIndex = false

        for i,v in pairs(text) do
            local chunkSize = 5
            local content = v:getcontent()
            local badChunk, badLine = should_filter(i, content)

            if badChunk then
                filter = true

            elseif badLine then
                text[i] = nil
            end

            if filter and ((string.find(content, petType) or (i - 1) == #text) or ((petType == validTypes[4] or petType == validTypes[2]) and string.find(content, ":"))) then
                if petType == "Titanic" or petType == "Shiny" then -- might kick me in the ass later but whatever YOLO!
                    filterIndex = i - 1
                else
                    filterIndex = i
                end
            end

            if filterIndex then
                if filterIndex == chunkSize then chunkSize = 4 end

                for i=filterIndex, (filterIndex - chunkSize), -1 do -- Thanks, heh! Nande. https://stackoverflow.com/a/41350070/15324861
                    text[i] = nil
                end

                i = i - chunkSize

                filterIndex = nil
                filter = false
            end
        end
    end

    local function convert_data(gemValue, demand)
        -- Calculates the value at which the auto reseller will sell at by factoring demand with orignal gem value
        gemValue, demand = gemValue:match('- (.+)'), demand:match('- (.+)') -- '- ' <-- match everything after '-', (.+) <-- include all charcaters

        local gemUnit = gemValue:match('%a+')
        local percentDecrease = 5 -- 5 percent decrease in selling price per point decrease in demand

        local figureAmount, upperScore, lowerScore, percentDifference, final;

        if gemUnit == "M" then
            figureAmount = 6

        elseif gemUnit == "B" then
            figureAmount = 9

        elseif gemUnit == "T" then
            figureAmount = 12

        elseif gemUnit == "Q" then
            figureAmount = 15
        else
            warn("Figure not found!")
        end

        gemValue = gemValue:gsub(gemUnit, '')

        if string.find(gemValue, "%p") then -- account for decimals
            figureAmount = figureAmount - 1

            gemValue = gemValue:gsub("[%p]", '')
        end

        for i=1,figureAmount do
            gemValue = gemValue .. "0" -- add figures
        end

        lowerScore, upperScore = demand:match("(.+)/(.+)")

        percentDifference = tonumber(upperScore) - tonumber(lowerScore)

        percentDecrease = (percentDecrease / 100) * percentDifference

        final = tonumber(gemValue) * (1 - percentDecrease)

        return final
    end

    filter_values()

    local count, targetIndex = 1 -- reindex values
    local gemValue, demand;

    for i,v in pairs(text) do -- Grab needed values
        local content = v:getcontent()

        if string.find(content, name) and string.len(content:gsub('[ \t]+%f[\r\n%z]', '')) == string.len(name) then -- strip any spaces at the end
            targetIndex = i
        end

        if targetIndex then
            if string.find(content, "Gem") then
                gemValue = content

            elseif string.find(content, "Demand") then
                demand = content

                targetIndex = nil
            end
        end

        count = count + 1
    end

    if gemValue and demand then
        gemValue = convert_data(gemValue, demand)
    else
        warn("Could not find necessary information for pet. Is the name correct?")
    end

    return gemValue
else
    warn("Invalid Type!")
end

-- Example: get_value("Huge", "Huge Pumpkin Cat")
