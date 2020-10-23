-- Electromagnet.lua --

--print("Electromagnet init")

Electromagnet = class( nil )
Electromagnet.maxChildCount = 0
Electromagnet.maxParentCount = 1
Electromagnet.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.bearing
Electromagnet.connectionOutput = sm.interactable.connectionType.none
Electromagnet.colorNormal = sm.color.new( 0xff3333ff ) --sm.color.new( 0x404040ff )
Electromagnet.colorHighlight = sm.color.new( 0xff5555ff ) --sm.color.new( 0x606060ff )
Electromagnet.poseWeightCount = 1
Electromagnet.magnetStrength = math.sqrt(1000 * 40) -- 1000 newton per second when two magnets have the same strength

-- Global table to keep track of all electromagnets
g_electromagnets = g_electromagnets or {}

function Electromagnet.server_onCreate( self )
    --print("[Electromagnet] server_onCreate")
    
    self.previousUvFrameIndex = 0
    table.insert(g_electromagnets, self)
    self:server_updateUvFrameIndex()
    self.parentPoseWeight = 0
end

function Electromagnet.server_onFixedUpdate( self, timeStep )
    local parent = self.interactable:getSingleParent()
    if parent then
        
        local selfForceMultiplier = self:getForceMultiplier()
        local condition = selfForceMultiplier ~= 0
        
        -- Update the visuals
        self:server_updateActive(condition)
        
        
        if condition and self.shape.body:isDynamic() then
            
            for _,v in ipairs(g_electromagnets) do
                
                -- The interactable sometimes doesn't exist when it's blown up in the same tick
                if v.interactable then
                
                    local vParent = v.interactable:getSingleParent()
                    
                    if vParent then
                        local vForceMultiplier = v:getForceMultiplier()
                        
                        if (self.shape.body.id ~= v.shape.body.id) and vForceMultiplier ~= 0 then
                            
                            local selfWorldPosition = sm.shape.getWorldPosition(self.shape)
                            local targetWorldPosition = sm.shape.getWorldPosition(v.shape)
                            
                            local delta = targetWorldPosition - selfWorldPosition
                            local distance2 = math.max(sm.vec3.length2(delta*4), 1) -- No insane impulses when the mangets are inside of eachother
                            
                            local impulse = delta:normalize() / distance2 * self.magnetStrength * v.magnetStrength * selfForceMultiplier * vForceMultiplier * timeStep
                            
                            --if distance2 < 1024 then
                            if impulse:length2() > 1 then -- Range of 32 blocks, adjusts with a different multiplier
                                
                                local selfPolarity = self:getPolarity()
                                if selfPolarity ~= "all" then
                                    if selfPolarity == v:getPolarity() then
                                        impulse = impulse * -1
                                    end
                                end
                                
                                -- Legacy code for converting global to local
                                --local localX = sm.shape.getRight(self.shape)
                                --local localY = sm.shape.getUp(self.shape)
                                --local localZ = localX:cross(localY) -- normal vector
                                --sm.physics.applyImpulse(self.shape, sm.vec3.new(impulse:dot(localX), -impulse:dot(localZ), impulse:dot(localY)))
                                
                                sm.physics.applyImpulse(self.shape, impulse, true)
                            end
                        end
                    end
                end
            end
        end
    else
        self:server_updateActive(false)
    end
    --self:server_updateUvFrameIndex()
end

function Electromagnet.server_updateActive(self, value)
    if self.interactable.active ~= value then
        self.interactable.active = value
        --print(value, self.interactable.active)
        self:server_updateUvFrameIndex(value)
    end
end

function Electromagnet.client_onFixedUpdate( self, timestamp )
    self.interactable:setPoseWeight(0, self.interactable.active and 1 or 0)
    
    if sm.isHost then
        local parent = self.interactable:getSingleParent()
        self.parentPoseWeight = parent and parent:getPoseWeight(0) or 0
    end
    --print(self.parentPoseWeight)
end

function Electromagnet.server_updateUvFrameIndex( self, active )
    local polarityOptions = {all = 0, north = 1, south = 2}
    
    self:getPolarity()
    
    if active == nil then
        active = self.interactable.active
    end
    
    local index = polarityOptions[self:getPolarity()]
    
    if active then
        index = index + 6
    end
    if index ~= self.previousUvFrameIndex then
        self.previousUvFrameIndex = index
        self.network:sendToClients("client_updateUvFrameIndex", index)
    end
    
    return index
end

function Electromagnet.client_updateUvFrameIndex( self, index )
    self.interactable:setUvFrameIndex(index)
    --print("uv")
end

function Electromagnet.getPolarity( self )
    local storage = tryLoad(self)
    if not storage then
        storage = {polarity = "all"}
        --self.storage:save(storage)
    end
    return storage.polarity
end





function Electromagnet.getForceMultiplier( self )
    local fm = 0
    
    local parent = self.interactable:getSingleParent()
    
    if parent:getType() == "electricEngine" or parent:getType() == "gasEngine" then
        local parentParent = parent:getSingleParent()
        if parentParent then
            if parentParent.active then
                fm = self.parentPoseWeight
            end
        end
    elseif parent:getType() == "scripted" then
        if parent:getPower() ~= 0 then
            return parent:getPower()
        else
            return parent.active and 1 or 0
        end
    else
        if parent.active then
            fm = 1
        end
    end
    
    return fm
end






function Electromagnet.client_onInteract( self, character, state )
    -- version check for backwards compatibility
    if state or sm.version:sub(1, 3) == "0.3" then
        sm.audio.play("GUI Shape rotate", sm.shape.getWorldPosition(self.shape))
        self.network:sendToServer("server_onSwitchPolarity")
    end
end

function Electromagnet.server_onSwitchPolarity( self )
    local storage = tryLoad(self)
    if storage then
        if storage.polarity == "all" then
            storage.polarity = "north"
        elseif storage.polarity == "north" then
            storage.polarity = "south"
        elseif storage.polarity == "south" then
            storage.polarity = "all"
        else
            storage.polarity = "all"
        end
    else
        storage = {polarity = "north"}
    end
    self.storage:save(storage)

    self:server_updateUvFrameIndex()
end

function tryLoad(em)
    local storage = em.storage
    local succes, returned = pcall(function(storage)
        local data = storage:load()
        return data
    end, storage)
    
    if not succes then
        print("Electromagnet with id =", em.interactable:getId(), "threw an error while loading its data:", returned, "\nResetting its polarity to \"all\".")
    end
    local data = succes and returned or nil
    --print(data, succes, returned)
    return data
end



