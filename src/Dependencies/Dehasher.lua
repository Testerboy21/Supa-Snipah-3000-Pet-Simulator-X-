local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Thank you for helping me understand shit https://v3rmillion.net/showthread.php?tid=1200968
local library = getrawmetatable(require(game.ReplicatedStorage.Library.Client.Network))
local v85 = library.__index
local v44 = getupvalue(v85, 1)
local fire = v44.Fire
local func;

if not func then
    for i,v in pairs(getgc()) do
        if type(v) == "function" and islclosure(v) and not is_synapse_function(v) then
            for j,k in pairs(debug.getprotos(v)) do -- or directly access with getinfo.name == "_getName" for old and new result
                if debug.getinfo(k).name == "HASH" then
                    func = v;
                end
            end
        end
    end
end

for i,v in pairs({}) do -- Desired remote name table
    if not ReplicatedStorage:FindFirstChild(v) then
        local remoteEvent, remoteFunc = 1,2 -- They identify event or func as a "1" or "2"

        for i2=remoteEvent,remoteFunc do
            local hashResult = func(i2,v)

            for i3,v3 in pairs(debug.getupvalues(fire)) do -- path to storage of remotes
                if debug.getinfo(v3).name == "_remoteEvent" then
                    local u10 = getupvalue(v3, 1)
                    local remoteStorage = getupvalue(u10, 1)

                    for i4,v4 in pairs(remoteStorage) do
                        for i5,v5 in pairs(v4) do
                            if hashResult == i5 then -- rename generic "RemoteX" name to hash
                                v5.Name = i5
                            end
                        end
                    end
                end
            end

            local found = ReplicatedStorage:FindFirstChild(hashResult) -- turn hash into original name

            if found then
                found.Name = v
            end
        end
    end
end
