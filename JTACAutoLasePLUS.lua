--[[
JTACAutoLase PLUS 1.2.4 Beta by Eagle86

Использован код из скрипта: JTACAutoLase	https://github.com/ciribob/DCS-JTACAutoLaze          

Добавлено:
1. Сообщения переведены на русский язык
2. Добавлена возможность выбирать группу для подсветки
3. Добавлена возможность выбрать тип ПВО для подсветки
4. Добавлена возможность выбрать тип статический для подсветки
5. Коалицию юнита jtac и противника указывать не нужно. Выбор делается исходя из коалиции юнита jtac
6. Добавлена возможность остановить подсветку отдельного JTAC или всех JTAC:  StopJTAC(jtacGroupName)  и StopAllJTAC() 
7. Добавлен таймер подсвета 
8. Добавлена новая функция InZone, которая автоматически создает 
   меню подсвета и разведки для приближающихся самолетов.

**Пример:**
**JTACAutoLase(       'JTAC1', 1113, false , "all" , 2 , "all", 30)** 
Параметры:

1: Имя группы JTAC
2: Код лазера - 1688 (Синие), 1113 (Красные) 
3: Дымы включены или нет (true, false)
4: Тип: vehicle - техника,troop - живая сила, sam - пво, static - статические, armor - бронетехника, artillery - артилерия, build - укрепления, all-все
5: Цвет дыма: Green = 0, Red = 1, White = 2, Orange = 3, Blue = 4
6: Название группы или все (all)
7: Время подсвета в секундах


Примечание: Тип - all для статических объектов не работает. 
Чтобы подсвечивать все статические объекты используйте тип - static, а группу - all
-------------------------------------------------------------------------------------------------------------------

Новая функция InZone - У ЛА которые влетают в зону JTAC автоматически создается меню для работы с ним.
В меню доступно: Выбор кода лазера (1113, 1688), подсвет всех целей, только пво, только статических.
Добавлена функция разведки в меню.

Пример:
Указываете имя группы JTAC, радиус (м.) зоны радиосвязи (меню), радиус (м.) зоны разведки, время подсвета 
	InZone       ( 'JTAC1',                    23000, 8000, 180)
StopInZone('JTAC1') - Остановка функции InZone для указанного JTAC**
]]



-- Конфигурация



JTAC_maxDistance = 10000 -- Как далеко JTAC может "видеть" в метрах

JTAC_smokeOn = true -- включает маркировку цели дымом, может быть переопределен

JTAC_smokeColour = 1 -- Зеленый = 0 , Красный= 1, Белый = 2, Оранжевый = 3, Синий        = 4

JTAC_jtacStatusF10 = true -- включить F10 JTAC статус меню

JTAC_location = true -- показывать сообщения о координатах цели. Может отображать одновременно только 2 цели

JTAC_lock =  "all" -- "vehicle" OR "troop" OR "all" forces JTAC to only lock vehicles or troops or all ground units 

-- ---------------------------------------------------------------------------------------------------------------------


GLOBAL_JTAC_LASE = {}
GLOBAL_JTAC_IR = {}
GLOBAL_JTAC_SMOKE = {}
GLOBAL_JTAC_UNITS = {} --lсписок подразделений  по команде F10 
GLOBAL_JTAC_CURRENT_TARGETS = {}
GLOBAL_JTAC_RADIO_ADDED = {} --keeps track of who's had the radio command added
GLOBAL_JTAC_LASER_CODES = {} -- keeps track of laser codes for jtac

GLOBAL_JTAC_TIMER = {}           -- таймер JTAC
GLOBAL_JTAC_TIMER_COUNT = {}
GLOBAL_JTAC_UNIT_VISIBLE = {} -- юниты в зоне
GLOBAL_JTAC_UNIT_TIMER = {}   -- таймер inZone
GLOBAL_SCOUT_UNIT = {}          -- юниты разведки

function JTACAutoLase(jtacGroupName, laserCode,smoke,lock,colour, targetGroupName, _time)

    if smoke == nil then
    
        smoke = JTAC_smokeOn  
    end

    if lock == nil then
    
        lock = JTAC_lock
    end

    if colour == nil then
    	colour = JTAC_smokeColour
    end

    GLOBAL_JTAC_LASER_CODES[jtacGroupName] = laserCode

    local jtacUnit
    local jtacGroup = Group.getByName(jtacGroupName)
	if jtacGroup ~= nil then 
	local jtacUnit = jtacGroup:getUnits()[1]
    SIDE_COALITION = jtacUnit:getCoalition()
	end

    --if jtacGroup == nil or #jtacGroup == 0 then
    if jtacGroup == nil then

        notify("Наш JTAC (ПАН) " .. jtacGroupName .. " уничтожен!", 10)

        --удалить из списка
        GLOBAL_JTAC_UNITS[jtacGroupName] = nil

        cleanupJTAC(jtacGroupName)
        return
    else

        jtacUnit = jtacGroup:getUnits()[1]
		SIDE_COALITION = jtacUnit:getCoalition()
        --добавить в список
        GLOBAL_JTAC_UNITS[jtacGroupName] = jtacUnit:getName()

    end
	
-- Поиск текущего Юнита

    if jtacUnit:isActive() == false then

        cleanupJTAC(jtacGroupName)
        env.info(jtacGroupName .. ' Не активно - Ожидание 30 секунд')
		GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName][timer] = timer.scheduleFunction(timerJTACAutoLase, { jtacGroupName, laserCode,smoke,lock,colour,targetGroupName, _time}, timer.getTime() + 30)
    return
    end

    local enemyUnit = getCurrentUnit(jtacUnit, jtacGroupName)
	
    if enemyUnit == nil and GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName] ~= nil then
		

        local tempUnitInfo = GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]
        local tempUnit = Unit.getByName(tempUnitInfo.name)
        
        
		if tempUnit ~= nil and tempUnit:getLife() > 0 and tempUnit:isActive() == true then
		
		notify(jtacGroupName .. ": Цель " .. tempUnitInfo.unitType .. " потеряна. Поиск целей. ", 10)
        else
        notify(jtacGroupName .. ": Цель " .. tempUnitInfo.unitType .. " уничтожена. Хорошая работа! ", 10)
        end

        --удалить из списка дымов
        GLOBAL_JTAC_SMOKE[tempUnitInfo.name] = nil

        -- удалить из списка целей
        GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName] = nil
        --стоп подсвет
        cancelLase(jtacGroupName)

    end


    if enemyUnit == nil then

    	enemyUnit = findNearestVisibleEnemy(jtacUnit,lock,targetGroupName) 

        if enemyUnit ~= nil then

		            -- store current target for easy lookup
            GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName] = { name = enemyUnit:getName(), unitType = enemyUnit:getTypeName(), unitId = enemyUnit:getID() }
        
	     	GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]["isStatic"] = false
            if lock == "static" then GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]["isStatic"] = true end

			
			if _time>0  and GLOBAL_JTAC_TIMER[jtacGroupName]==nil then GLOBAL_JTAC_TIMER[jtacGroupName] = timer.scheduleFunction(timerStopJTAC, {jtacGroupName}, timer.getTime() + _time)  
			                          GLOBAL_JTAC_TIMER_COUNT[jtacGroupName] =  timer.scheduleFunction(timerCountJTAC, {jtacGroupName}, timer.getTime() + _time - 30)  
									  end		--------------------------  ТАЙМЕР
		    local msg = jtacGroupName .. ": Подсвечиваю новую цель " .. enemyUnit:getTypeName() .. ', код лазера: ' .. laserCode .. "\n" .. getPositionString(enemyUnit)
			if _time>0 then  msg = msg .. "\nдлительность подсвета - " .. _time .. " сек. (" .. roundNumber (_time/60,2) .. " мин.)" end
			notify(msg, 10)
	        
            -- создать дым
            if smoke == true then

                --создание первого дыма
                createSmokeMarker(enemyUnit,colour)
            end
            else trigger.action.outSoundForCoalition(SIDE_COALITION, "jtac_visible.ogg") trigger.action.outText(jtacGroupName .. ": нет видимых целей.",10) StopJTAC(jtacGroupName) end
    end


	
    if enemyUnit ~= nil then

        laseUnit(enemyUnit, jtacUnit, jtacGroupName, laserCode)

        GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName][timer] = timer.scheduleFunction(timerJTACAutoLase, { jtacGroupName, laserCode, smoke, lock, colour, targetGroupName, _time }, timer.getTime() + 1) 
		if smoke == true then
            local nextSmokeTime = GLOBAL_JTAC_SMOKE[enemyUnit:getName()]

            --recreate smoke marker after 5 mins
            if nextSmokeTime ~= nil and nextSmokeTime < timer.getTime() then

                createSmokeMarker(enemyUnit, colour)
            end
        end

    else
        -- stop lazing the old spot
        cancelLase(jtacGroupName)
		if enemyUnit ~= nil then GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName][timer] = timer.scheduleFunction(timerJTACAutoLase, { jtacGroupName, laserCode, smoke,lock,colour,targetGroupName, _time }, timer.getTime() + 5) end

		end
end


-- таймер СТОП
function timerStopJTAC(args)
    StopJTAC(args[1])
end

function timerCountJTAC(args)
   CountJTAC(args[1])
end

function CountJTAC(jtacGroupName)
   notify (jtacGroupName .. ": Подсвет остановится через 30 секунд.", 5)
   trigger.action.outSoundForCoalition(SIDE_COALITION, "Message.ogg")
   timer.removeFunction(GLOBAL_JTAC_TIMER_COUNT[jtacGroupName])  
   GLOBAL_JTAC_TIMER_COUNT[jtacGroupName]=nil  -- СПИСОК ТАЙМЕРА - 30 СЕКУНД
end

function StopAllJTAC() -- ОСТАНОВКА ВСЕХ ПАН
	for key,value in pairs(GLOBAL_JTAC_UNITS) do
    StopJTAC(key)
    end
	notify ("Подсвет со всех JTAC остановлен.", 5)
end

function StopJTAC(jtacGroupName) -- ОСТАНОВКА УКАЗАННОГО ПАН
	
 	
    if GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]~=nil then timer.removeFunction(GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName][timer]); 	 
                                                                                                        	trigger.action.outSoundForCoalition(SIDE_COALITION, "jtac_end.ogg")  notify (jtacGroupName .. ": подсвет закончил", 5) end
																											
 																											
																											
 	if GLOBAL_JTAC_TIMER~=nil and GLOBAL_JTAC_TIMER[jtacGroupName]~=nil then  timer.removeFunction(GLOBAL_JTAC_TIMER[jtacGroupName])  
																															   GLOBAL_JTAC_TIMER[jtacGroupName] = nil  end -- СПИСОК ТАЙМЕРА
 
																															   
	if GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]~=nil then cleanupJTAC(jtacGroupName) end
	
 
	
    if GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]~=nil then GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName] = nil end
 
	
	if GLOBAL_JTAC_UNIT_VISIBLE~=nil then zeroJtac(jtacGroupName) end
	
 
end



-- used by the timer function
function timerJTACAutoLase(args)
    JTACAutoLase(args[1], args[2], args[3],args[4],args[5],args[6],args[7]) 
end

function cleanupJTAC(jtacGroupName)
    -- clear laser - just in case
    cancelLase(jtacGroupName)

    -- Cleanup
    GLOBAL_JTAC_UNITS[jtacGroupName] = nil
    GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName] = nil
end



function notify(message, displayFor)
    trigger.action.outTextForCoalition(SIDE_COALITION, message, displayFor)
    -- trigger.action.outSoundForCoalition(SIDE_COALITION, "radiobeep.ogg")
end

function createSmokeMarker(enemyUnit,colour)

    --recreate in 5 mins
    GLOBAL_JTAC_SMOKE[enemyUnit:getName()] = timer.getTime() + 300.0

    -- move smoke 2 meters above target for ease
    local enemyPoint = enemyUnit:getPoint()
    trigger.action.smoke({ x = enemyPoint.x, y = enemyPoint.y + 2.0, z = enemyPoint.z }, colour)
end

function cancelLase(jtacGroupName)

    local tempLase = GLOBAL_JTAC_LASE[jtacGroupName]

    if tempLase ~= nil then
        Spot.destroy(tempLase)
        GLOBAL_JTAC_LASE[jtacGroupName] = nil

        tempLase = nil
    end

    local tempIR = GLOBAL_JTAC_IR[jtacGroupName]

    if tempIR ~= nil then
        Spot.destroy(tempIR)
        GLOBAL_JTAC_IR[jtacGroupName] = nil
        tempIR = nil
    end
end

function laseUnit(enemyUnit, jtacUnit, jtacGroupName, laserCode)

    --cancelLase(jtacGroupName)

    local spots = {}

    local enemyVector = enemyUnit:getPoint()
    local enemyVectorUpdated = { x = enemyVector.x, y = enemyVector.y + 2.0, z = enemyVector.z }

    local oldLase = GLOBAL_JTAC_LASE[jtacGroupName]
    local oldIR = GLOBAL_JTAC_IR[jtacGroupName]

    if oldLase == nil or oldIR == nil then

        -- create lase

        local status, result = pcall(function()
            spots['irPoint'] = Spot.createInfraRed(jtacUnit, { x = 0, y = 2.0, z = 0 }, enemyVectorUpdated)
            spots['laserPoint'] = Spot.createLaser(jtacUnit, { x = 0, y = 2.0, z = 0 }, enemyVectorUpdated, laserCode)
            return spots
        end)

        if not status then
            env.error('ERROR: ' .. assert(result), false)
        else
            if result.irPoint then

                --    env.info(jtacUnit:getName() .. ' placed IR Pointer on '..enemyUnit:getName())

                GLOBAL_JTAC_IR[jtacGroupName] = result.irPoint --store so we can remove after

            end
            if result.laserPoint then

                --	env.info(jtacUnit:getName() .. ' is Lasing '..enemyUnit:getName()..'. CODE:'..laserCode)

                GLOBAL_JTAC_LASE[jtacGroupName] = result.laserPoint
            end
        end

    else

        -- update lase

        if oldLase~=nil then
            oldLase:setPoint(enemyVectorUpdated)
        end

        if oldIR ~= nil then
            oldIR:setPoint(enemyVectorUpdated)
        end

    end

end



-- получить выбранный в данный момент юнит и проверить, что он все еще досигаем
function getCurrentUnit(jtacUnit, jtacGroupName)
    local unit = nil

	-- Проверяем на статический объект
	local isStatic=false
	if GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]~=nil and GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]["isStatic"] == true then isStatic=true end
	---------------------------------------
	
    if GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName] ~= nil then
        unit = Unit.getByName(GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName].name)
    end
	
	if isStatic == true then  unit = StaticObject.getByName(GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName].name) end


    local tempPoint = nil
    local tempDist = nil
    local tempPosition = nil

    local jtacPosition = jtacUnit:getPosition()
    local jtacPoint = jtacUnit:getPoint()

	
    if (isStatic == true  and unit ~= nil and unit:getLife()>0) or (unit ~= nil and unit:getLife() > 0 and unit:isActive() == true) then

        -- вычислить дистанцию
        tempPoint = unit:getPoint()

        tempDist = getDistance(tempPoint.x, tempPoint.z, jtacPoint.x, jtacPoint.z)
        if tempDist < JTAC_maxDistance then
            -- вычислить видимость

            -- check slightly above the target as rounding errors can cause issues, plus the unit has some height anyways
            local offsetEnemyPos = { x = tempPoint.x, y = tempPoint.y + 2.0, z = tempPoint.z }
            local offsetJTACPos = { x = jtacPoint.x, y = jtacPoint.y + 2.0, z = jtacPoint.z }

            if land.isVisible(offsetEnemyPos, offsetJTACPos) then
                return unit
            end
        end
    end
    return nil
end

-- ПОИСК 
-- Найти ближайшую цель для JTAC, что не заблокирована местностью
function findNearestVisibleEnemy(jtacUnit, targetType,targetGroupName)

    local x = 1
    local i = 1

    local units = nil
	
    local groupName = targetGroupName

    local nearestUnit = nil
    
	local nearestDistance = JTAC_maxDistance


    local jtacPoint = jtacUnit:getPoint()
    local jtacPosition = jtacUnit:getPosition()

    local tempPoint = nil
    local tempPosition = nil

    local tempDist = nil

	local enemyCOALITION = nil
	
	local isStatic = false
	if targetType == "static" then isStatic=true end
	
	
	-- Получить все группы каолиции
	 if isStatic~=true then
	 if SIDE_COALITION == coalition.side.RED then 
	     enemyCOALITION = coalition.getGroups(coalition.side.BLUE, Group.Category.GROUND) 
		 else enemyCOALITION = coalition.getGroups(coalition.side.RED, Group.Category.GROUND) end
     else
		 if SIDE_COALITION == coalition.side.RED then
		 enemyCOALITION=coalition.getStaticObjects(coalition.side.BLUE) 
		 else enemyCOALITION = coalition.getStaticObjects(coalition.side.RED) end
     end


    -- Цикл групп
	    for i = 1, #enemyCOALITION do

	if targetGroupName == "all"  then  groupName = enemyCOALITION[i]:getName() end     -- Выбраны все
   	if isStatic == true then units=enemyCOALITION else units = getGroup(groupName) end -- Выбран статик или группа
		
		if groupName~= nil or isStatic == true then

		if #units > 0 then
    -- Цикл юнитов
                for x = 1, #units do
	-- проверка, JTAC уже разработал или нет по этому юниту
                    local targeted = alreadyTarget(jtacUnit,units[x])
                    local allowedTarget = true
    			    
                    if targetType == "vehicle" then
                        
                        allowedTarget = isVehicle(units[x])

                    elseif targetType == "troop" then

                        allowedTarget = isInfantry(units[x])

					elseif targetType == "sam" then

                        allowedTarget = isSam(units[x])
						
					elseif targetType == "armor" then

                        allowedTarget = isArmor(units[x])

            		elseif targetType == "artillery" then

                        allowedTarget = isArtillery(units[x])

    				elseif targetType == "build" then

                        allowedTarget = isBuild(units[x])
						
						
					elseif isStatic == true and targetGroupName~="all" and targetGroupName ~= units[x]:getName() then -- Статик
					
                        allowedTarget = false	
						
                   	end
                
     				if (isStatic == true or units[x]:isActive() == true) and targeted == false and allowedTarget == true then
                        -- вычислить дистанцию
                        tempPoint = units[x]:getPoint()
                        tempDist = getDistance(tempPoint.x, tempPoint.z, jtacPoint.x, jtacPoint.z)
                        if tempDist < JTAC_maxDistance and tempDist < nearestDistance then
                            local offsetEnemyPos = { x = tempPoint.x, y = tempPoint.y + 2.0, z = tempPoint.z }
                            local offsetJTACPos = { x = jtacPoint.x, y = jtacPoint.y + 2.0, z = jtacPoint.z }
                            -- вычислить видимость
                            if land.isVisible(offsetEnemyPos, offsetJTACPos) then

                                nearestDistance = tempDist
                                nearestUnit = units[x]
                             end

                        end
                    end
                end
            end
        end
    end
    


    if nearestUnit == nil then
        return nil
    end


    return nearestUnit
end


function alreadyTarget(jtacUnit, enemyUnit)

    for y , jtacTarget in pairs(GLOBAL_JTAC_CURRENT_TARGETS) do

        if jtacTarget.unitId == enemyUnit:getID() then

            return true
        end

    end

    return false

end


-- Returns only alive units from group but the group / unit may not be active

function getGroup(groupName)

    local groupUnits = Group.getByName(groupName)

    local filteredUnits = {} --contains alive units
    local x = 1

    if groupUnits ~= nil then

        groupUnits = groupUnits:getUnits()

        if groupUnits ~= nil and #groupUnits > 0 then
            for x = 1, #groupUnits do
                if groupUnits[x]:getLife() > 0 then
                    table.insert(filteredUnits, groupUnits[x])
                end
            end
        end
    end

    return filteredUnits
end

-- Distance measurement between two positions, assume flat world

function getDistance(xUnit, yUnit, xZone, yZone)
    local xDiff = xUnit - xZone
    local yDiff = yUnit - yZone

    return math.sqrt(xDiff * xDiff + yDiff * yDiff)
end

-- gets the JTAC status and displays to coalition units
function getJTACStatus(gID)

    --returns the status of all JTAC units

	

	
    local jtacGroupName = nil
    local jtacUnit = nil
    local jtacUnitName = nil

	
    local message = "///// СТАТУС ГРУПП JTAC: \n"

    for jtacGroupName, jtacUnitName in pairs(GLOBAL_JTAC_UNITS) do
        --look up units
        jtacUnit = Unit.getByName(jtacUnitName)

        if jtacUnit ~= nil and jtacUnit:getLife() > 0 and jtacUnit:isActive() == true then

            local enemyUnit = getCurrentUnit(jtacUnit, jtacGroupName)

            local laserCode =  GLOBAL_JTAC_LASER_CODES[jtacGroupName]

            if laserCode == nil then
            	laserCode = "UNKNOWN"
            end
            if enemyUnit ~= nil and enemyUnit:getLife() > 0 and ((GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]~=nil and GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]["isStatic"] == true) or enemyUnit:isActive() == true) then
--            if enemyUnit ~= nil and enemyUnit:getLife() > 0 and enemyUnit:isActive() == true then
                message = message .. "\n" .. jtacGroupName .. ": Цель " .. enemyUnit:getTypeName().. ", код лазера: ".. laserCode .. "\n" .. getPositionString(enemyUnit) .. "\n"
            else
			   if GLOBAL_JTAC_UNITS[jtacGroupName]~=nil then message = message .. "\n" .. jtacGroupName .. ": Цели в радиусе " .. JTAC_maxDistance/1000 .. " км. не обнаружены, работу закончил. \nМои " .. getPositionString(jtacUnit) .."\n" end
			end
        end
    end
    if gID~=nil then trigger.action.outTextForGroup( gID, message, 10, true)  else notify(message,4) end    
	
	for i,v in pairs(GLOBAL_SCOUT_UNIT) do
--	notify(GLOBAL_SCOUT_UNIT[i]["jtac"] .. " разведка ",10) 
	trigger.action.outTextForGroup(gID, GLOBAL_SCOUT_UNIT[i]["jtac"] .. ": разведка ",10) 
	end
	
end



function timerInZone (args)
    InZone(args[1], args[2],args[3],args[4]) 
end

function timerScout (args)
    inScout(args[1], args[2]) 
end


function TableConcat(t1,t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end


function zeroJtac(jtacGroupName)
	   for k, v in pairs(GLOBAL_JTAC_UNIT_VISIBLE) do
        GLOBAL_JTAC_UNIT_VISIBLE[k]["jtac"][jtacGroupName]=nil 
       end
	   if GLOBAL_SCOUT_UNIT~=nil and  GLOBAL_SCOUT_UNIT[jtacGroupName][timer]~=nil then timer.removeFunction(GLOBAL_SCOUT_UNIT[jtacGroupName][timer]); GLOBAL_SCOUT_UNIT[jtacGroupName]=nil end
end

function StopInZone(jtacGroupName,_distanceScout) 
      if GLOBAL_JTAC_UNIT_TIMER[jtacGroupName]~=nil and GLOBAL_JTAC_UNIT_TIMER[jtacGroupName][timer]~=nil then timer.removeFunction(GLOBAL_JTAC_UNIT_TIMER[jtacGroupName][timer]);	end
      for k, v in pairs(GLOBAL_JTAC_UNIT_VISIBLE) do
    	clearMenu(v["group"],jtacGroupName,_distanceScout) 
    end	  
end


-- РАЗВЕДКА 
function inScout(jtacGroupName,_distanceScout) 



    local x = 1
    local i = 1
	local tempGroup = nil
    local jtacGroup = Group.getByName(jtacGroupName)
	if jtacGroup == nil then return nil end
    local jtacUnit = jtacGroup:getUnits()[1]	
    local units = nil
    local groupName = nil
    local nearestUnit = nil
    local jtacPoint = jtacUnit:getPoint()
    local jtacPosition = jtacUnit:getPosition()
	local s_coalition = jtacUnit:getCoalition()
    local tempPoint = nil
    local tempPosition = nil
    local tempDist = nil
	local enemyCOALITION = nil
	
    SIDE_COALITION = jtacUnit:getCoalition()
	
	if GLOBAL_SCOUT_UNIT[jtacGroupName]==nil then GLOBAL_SCOUT_UNIT[jtacGroupName] = { timer = nil, target = nil, jtac = jtacGroupName} end
	
	if GLOBAL_SCOUT_UNIT[jtacGroupName][timer]==nil then trigger.action.outText(jtacGroupName .. ": поиск целей на дистанции " .. roundNumber (_distanceScout,0) .. " м.",5)
                                        for k,v in pairs(GLOBAL_JTAC_UNIT_VISIBLE) do
										  if Group.getByName(v["group"])~=nil then clearLaseMenu(v["group"],jtacGroupName,_distanceScout) else 
										  v["group"]=nil 
                                          end
										  end
	
                                                                        	end
	
	if  s_coalition == coalition.side.RED then enemyCOALITION =  coalition.getGroups(coalition.side.BLUE, Group.Category.GROUND)  else
	                                                       enemyCOALITION =  coalition.getGroups(coalition.side.RED, Group.Category.GROUND)    end
	
	    -- Цикл групп
	    for i = 1, #enemyCOALITION do

	    groupName = enemyCOALITION[i]:getName() 
   	    units = getGroup(groupName)  -- Выбрана группа
		
		if groupName~= nil then

		if #units > 0 then
    -- Цикл юнитов
                for x = 1, #units do
                        -- вычислить дистанцию
                        tempPoint = units[x]:getPoint()
                        tempDist = getDistance(tempPoint.x, tempPoint.z, jtacPoint.x, jtacPoint.z)
		
	                 	 local offsetEnemyPos = { x = tempPoint.x, y = tempPoint.y + 2.0, z = tempPoint.z }
                         local offsetJTACPos = { x = jtacPoint.x, y = jtacPoint.y + 2.0, z = jtacPoint.z }
	                   
                        if tempDist < _distanceScout and land.isVisible(offsetEnemyPos, offsetJTACPos)  then -- проверяем дистанцию
						tempGroup = Group.getByName(Unit.getGroup(units[x]):getName())
						--GLOBAL_SCOUT_UNIT[jtacGroupName][timer][target] = tempGroup:getName()
						trigger.action.outSoundForCoalition(s_coalition, "jtac_scout.ogg")
						trigger.action.outText(jtacGroupName.. ": обнаружил группу противника " .. tempGroup:getName() .. " дистанция " .. roundNumber (tempDist,0) .. " м." ,5)
					    zeroJtac(jtacGroupName)
						return tempGroup:getName()
					    end -- if дистанция 
	     end
		 end
		 end 
		 end 
  	GLOBAL_SCOUT_UNIT[jtacGroupName][timer] =  timer.scheduleFunction(timerScout, {jtacGroupName, _distanceScout},timer.getTime() + 2 )  -- Вызов таймера Scout
	
	
end

-- InZone  Menu 
-- проверить группы самолетов в зоне JTAC
function InZone(jtacGroupName,distanceRadio,_distanceScout, _time) 
if  _distanceScout~=nil then
    local x = 1
    local i = 1
	local tempGroup = nil
    local jtacGroup = Group.getByName(jtacGroupName)
	if jtacGroup == nil then return nil end
    local jtacUnit = jtacGroup:getUnits()[1]	
    local units = nil
    local groupName = nil
    local jtacPoint = jtacUnit:getPoint()
    local jtacPosition = jtacUnit:getPosition()
	local s_coalition = jtacUnit:getCoalition()
    local tempPoint = nil
    local tempPosition = nil
    local tempDist = nil
	local enemyCOALITION = nil
   
    SIDE_COALITION = jtacUnit:getCoalition()
	-- Получить все авиа-группы каолиции
	enemyCOALITION = TableConcat (coalition.getGroups(s_coalition, Group.Category.HELICOPTER) , coalition.getGroups(s_coalition, Group.Category.AIRPLANE) )	 
	
	    -- Цикл групп
	    for i = 1, #enemyCOALITION do

	    groupName = enemyCOALITION[i]:getName() 
   	    units = getGroup(groupName)  -- Выбрана группа
		
		if groupName~= nil then

		if #units > 0 then
    -- Цикл юнитов
                for x = 1, #units do
                        -- вычислить дистанцию
                        tempPoint = units[x]:getPoint()
                        tempDist = getDistance(tempPoint.x, tempPoint.z, jtacPoint.x, jtacPoint.z)
		
                        if tempDist < distanceRadio then -- проверяем дистанцию

						tempGroup = Group.getByName(Unit.getGroup(units[x]):getName())

	if GLOBAL_JTAC_UNIT_VISIBLE[groupName] == nil  then laseMenu(tempGroup:getName(), jtacGroupName,_time,_distanceScout)  end 
	local _table = GLOBAL_JTAC_UNIT_VISIBLE[groupName]["jtac"][jtacGroupName] 
	if _table == nil  then laseMenu(tempGroup:getName(), jtacGroupName,_time,_distanceScout)  end 
	if GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]~=nil and GLOBAL_JTAC_UNIT_VISIBLE[groupName] ~= nil and GLOBAL_JTAC_UNIT_VISIBLE[groupName]["jtac"][jtacGroupName]~=nil then tempGroup = Group.getByName(Unit.getGroup(units[x]):getName())  clearLaseMenu(tempGroup:getName(),jtacGroupName,_distanceScout)  end 

	                        else 
							 tempGroup = Group.getByName(Unit.getGroup(units[x]):getName())  
						  	 if GLOBAL_JTAC_UNIT_VISIBLE[tempGroup:getName()]~= nil then
							 GLOBAL_JTAC_UNIT_VISIBLE[tempGroup:getName()]["jtac"][jtacGroupName]=nil 
							 clearMenu(tempGroup:getName(),jtacGroupName,_distanceScout) 					   
							 end 
		                end 
	     end
		 end
		 end 
		 end 
         if GLOBAL_JTAC_UNIT_TIMER[jtacGroupName]==nil then GLOBAL_JTAC_UNIT_TIMER[jtacGroupName]= {timer = nil} end
	    GLOBAL_JTAC_UNIT_TIMER[jtacGroupName][timer] = timer.scheduleFunction(timerInZone, {jtacGroupName,distanceRadio,_distanceScout,_time},timer.getTime() + 2 )  -- Вызов таймера InZone
   end				
end

-- Очистить меню подсвета
function clearLaseMenu(groupName,jtacGroupName,_distanceScout) 
   local  gID = Group.getID(Group.getByName(groupName))
  -- local _sc = 'Scout - '.. tostring (_distanceScout / 1000)
   missionCommands.removeItemForGroup(gID, {jtacGroupName,"код лазера 1113"} )  		
   missionCommands.removeItemForGroup(gID, {jtacGroupName,"код лазера 1688"} )   	
   missionCommands.removeItemForGroup(gID, {jtacGroupName,"Произвести разведку - " .. _distanceScout / 1000 .. " км."} )
   end


 -- Очистить все меню у группы 
function clearMenu(groupName,jtacGroupName,_distanceScout) 
   local gID = Group.getID(Group.getByName(groupName))
   clearLaseMenu(groupName,jtacGroupName,_distanceScout) 
   missionCommands.removeItemForGroup(gID, {jtacGroupName,"Остановить работу JTAC"} )  		
   missionCommands.removeItemForGroup(gID, {jtacGroupName,"Статус всех JTAC"} )  		
   missionCommands.removeItemForGroup(gID, {jtacGroupName})   
end



function laseMenu(groupName, jtacGroupName,_time,_distanceScout)
-- Меню для групп в зоне JTAC
   local gID = Group.getID(Group.getByName(groupName))
   if GLOBAL_JTAC_UNIT_VISIBLE[groupName]==nil then GLOBAL_JTAC_UNIT_VISIBLE[groupName] = { jtac= {}, group = groupName, timer = nil }end
   GLOBAL_JTAC_UNIT_VISIBLE[groupName]["jtac"][jtacGroupName] = true 
   -- Очистка меню
   clearMenu(groupName,jtacGroupName,_distanceScout)  
   -- Создание меню

   missionCommands.addSubMenuForGroup(gID, jtacGroupName)
   missionCommands.addSubMenuForGroup(gID, "код лазера 1113", {jtacGroupName})
   missionCommands.addSubMenuForGroup(gID, "код лазера 1688", {jtacGroupName})
   
if  GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]==nil then
   missionCommands.addCommandForGroup(gID, tostring(_time/60) .. " минут(ы) - ПВО", {jtacGroupName,"код лазера 1113"}, JTACAutoLase, jtacGroupName,1113,false,"sam",2,"all", _time )  
   missionCommands.addCommandForGroup(gID, tostring(_time/60) .. " минут(ы) - Бронетехника", {jtacGroupName,"код лазера 1113"}, JTACAutoLase, jtacGroupName,1113,false,"armor",2,"all", _time ) 
   missionCommands.addCommandForGroup(gID, tostring(_time/60) .. " минут(ы) - Артилерия", {jtacGroupName,"код лазера 1113"}, JTACAutoLase, jtacGroupName,1113,false,"artillery",2,"all", _time ) 
   missionCommands.addCommandForGroup(gID, tostring(_time/60) .. " минут(ы) - Укрепления", {jtacGroupName,"код лазера 1113"}, JTACAutoLase, jtacGroupName,1113,false,"build",2,"all", _time ) 
   missionCommands.addCommandForGroup(gID, tostring(_time/60) .. " минут(ы) - Статические", {jtacGroupName,"код лазера 1113"}, JTACAutoLase, jtacGroupName,1113,false,"static",2,"all", _time )        
   missionCommands.addCommandForGroup(gID, tostring(_time/60) .. " минут(ы) - Все цели", {jtacGroupName,"код лазера 1113"}, JTACAutoLase, jtacGroupName,1113,false,"all",2,"all", _time ) 
   missionCommands.addCommandForGroup(gID, tostring(_time/60) .." минут(ы) - ПВО", {jtacGroupName,"код лазера 1688"}, JTACAutoLase, jtacGroupName,1688,false,"sam",2,"all", _time )  
   missionCommands.addCommandForGroup(gID, tostring(_time/60) .. " минут(ы) - Бронетехника", {jtacGroupName,"код лазера 1688"}, JTACAutoLase, jtacGroupName,1688,false,"armor",2,"all", _time ) 
   missionCommands.addCommandForGroup(gID, tostring(_time/60) .. " минут(ы) - Артилерия", {jtacGroupName,"код лазера 1688"}, JTACAutoLase, jtacGroupName,1688,false,"artillery",2,"all", _time ) 
   missionCommands.addCommandForGroup(gID, tostring(_time/60) .. " минут(ы) - Укрепления", {jtacGroupName,"код лазера 1688"}, JTACAutoLase, jtacGroupName,1688,false,"build",2,"all", _time ) 
   missionCommands.addCommandForGroup(gID, tostring(_time/60) .." минут(ы) - Статические", {jtacGroupName,"код лазера 1688"}, JTACAutoLase, jtacGroupName,1688,false,"static",2,"all", _time )        
   missionCommands.addCommandForGroup(gID, tostring(_time/60) .." минут(ы) - Все цели", {jtacGroupName,"код лазера 1688"}, JTACAutoLase, jtacGroupName,1688,false,"all",2,"all", _time ) 
   missionCommands.addCommandForGroup(gID, "Произвести разведку - " .. _distanceScout / 1000 .. " км.", {jtacGroupName}, inScout, jtacGroupName , _distanceScout) 
                                                                              end
   missionCommands.addCommandForGroup(gID, "Остановить работу JTAC", {jtacGroupName}, StopJTAC, jtacGroupName )  
   missionCommands.addCommandForGroup(gID, "Статус всех JTAC", {jtacGroupName}, getJTACStatus, gID )  
   trigger.action.outTextForGroup( gID, jtacGroupName .. " жду указаний.", 4,nil)  
end




-- Radio command for players (F10 Menu)
function addRadioCommands()

    timer.scheduleFunction(addRadioCommands, nil, timer.getTime() + 10)
	if SIDE_COALITION == nil then return nil end 
    local blueGroups = coalition.getGroups(SIDE_COALITION)
    local x = 1

    if blueGroups ~= nil then
        for x, tmpGroup in pairs(blueGroups) do
            local index = "GROUP_" .. Group.getID(tmpGroup)
            if GLOBAL_JTAC_RADIO_ADDED[index] == nil then
                GLOBAL_JTAC_RADIO_ADDED[index] = true
            end
        end
    end
end

function isBuild(unit) -- Укрепление

 if unit:getDesc()["attributes"]["Fortifications"]==true then return true  end
 return false

end

function isArmor(unit) -- Бронетехника

 if unit:getDesc()["attributes"]["Armored vehicles"]==true then return true  end
 return false

end

function isArtillery(unit) -- Артилерия

 if unit:getDesc()["attributes"]["Artillery"]==true then return true end
 return false

end



function isInfantry(unit)

    local typeName = unit:getTypeName()

    --type coerce tostring
    typeName = string.lower(typeName.."")

    local soldierType = { "infantry","paratrooper","stinger","manpad"}

    for key,value in pairs(soldierType) do
        if string.match(typeName, value) then
            return true
        end
    end

    return false

end

function isSam(unit) -- ПВО
 
 if unit:getDesc()["attributes"]["Air Defence"]==true then return true end
 return false
 
end


-- assume anything that isnt soldier is vehicle
function isVehicle(unit)

    if isInfantry(unit) then
        return false
    end

    return true

end
    

function getPositionString(unit)

    if JTAC_location == false then
        return ""
    end

	local latLngStr = latLngString(unit,3)

	local mgrsString = MGRSString(coord.LLtoMGRS(coord.LOtoLL(unit:getPosition().p)),5)

	return "координаты " .. latLngStr .. " - MGRS "..mgrsString

end

-- source of Function MIST - https://github.com/mrSkortch/MissionScriptingTools/blob/master/mist.lua
function latLngString(unit, acc)

	local lat, lon = coord.LOtoLL(unit:getPosition().p)

	local latHemi, lonHemi
	if lat > 0 then
		latHemi = 'N'
	else
		latHemi = 'S'
	end
	
	if lon > 0 then
		lonHemi = 'E'
	else
		lonHemi = 'W'
	end
	
	lat = math.abs(lat)
	lon = math.abs(lon)
	
	local latDeg = math.floor(lat)
	local latMin = (lat - latDeg)*60
	
	local lonDeg = math.floor(lon)
	local lonMin = (lon - lonDeg)*60
	
  -- degrees, decimal minutes.
	latMin = roundNumber(latMin, acc)
	lonMin = roundNumber(lonMin, acc)
	
	if latMin == 60 then
		latMin = 0
		latDeg = latDeg + 1
	end
		
	if lonMin == 60 then
		lonMin = 0
		lonDeg = lonDeg + 1
	end
	
	local minFrmtStr -- create the formatting string for the minutes place
	if acc <= 0 then  -- no decimal place.
		minFrmtStr = '%02d'
	else
		local width = 3 + acc  -- 01.310 - that's a width of 6, for example.
		minFrmtStr = '%0' .. width .. '.' .. acc .. 'f'
	end
	
	return string.format('%02d', latDeg) .. ' ' .. string.format(minFrmtStr, latMin) .. '\'' .. latHemi .. '   '
   .. string.format('%02d', lonDeg) .. ' ' .. string.format(minFrmtStr, lonMin) .. '\'' .. lonHemi

end

-- source of Function MIST - https://github.com/mrSkortch/MissionScriptingTools/blob/master/mist.lua
 function MGRSString(MGRS, acc) 
	if acc == 0 then
		return MGRS.UTMZone .. ' ' .. MGRS.MGRSDigraph
	else
		return MGRS.UTMZone .. ' ' .. MGRS.MGRSDigraph .. ' ' .. string.format('%0' .. acc .. 'd', roundNumber(MGRS.Easting/(10^(5-acc)), 0)) 
		       .. ' ' .. string.format('%0' .. acc .. 'd', roundNumber(MGRS.Northing/(10^(5-acc)), 0))
	end
end
-- From http://lua-users.org/wiki/SimpleRound
 function roundNumber(num, idp)
  local mult = 10^(idp or 0)
  return math.floor(num * mult + 0.5) / mult
end


-- добавление радиокоманды
if JTAC_jtacStatusF10 == true then
    timer.scheduleFunction(addRadioCommands, nil, timer.getTime() + 1)
end

trigger.action.outText('JTACAutoLase PLUS Beta 1.2.5 by Eagle86', 2);