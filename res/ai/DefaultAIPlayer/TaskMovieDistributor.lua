-- File: TaskMovieDistributor
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
_G["TaskMovieDistributor"] = class(AITask, function(c)
	AITask.init(c)	-- must init base!
	c.Id = _G["TASK_MOVIEDISTRIBUTOR"]
	c.TargetRoom = TVT.ROOM_MOVIEAGENCY
	c.MoviesAtDistributor = nil
	c.MoviesAtAuctioneer = nil
	c.NiveauChecked = false
	c.MovieCount = 0
	c.CheckMode = 0
	c.MovieList = nil
	c.BuyStartProgrammeJob = nil
	c.BuyRequisitedLicencesJob = nil
	c.CheckMoviesJob = nil
	c.AppraiseMovies = nil
	c.ProgrammesPossessed = 0
	c.CurrentBargainBudget = 0
	c:ResetDefaults()
end)

function TaskMovieDistributor:typename()
	return "TaskMovieDistributor"
end

function TaskMovieDistributor:ResetDefaults()
	self.BudgetWeight = 8
	self.BasePriority = 3
	self.NeededInvestmentBudget = 75000
	self.InvestmentPriority = 6
end

function TaskMovieDistributor:Activate()
	-- Was getan werden soll:
	self.BuyStartProgrammeJob = JobBuyStartProgramme()
	self.BuyStartProgrammeJob.MovieDistributorTask = self

	self.BuyRequisitedLicencesJob = JobBuyRequisitedLicences()
	self.BuyRequisitedLicencesJob.MovieDistributorTask = self

	self.CheckMoviesJob = JobCheckMovies()
	self.CheckMoviesJob.MovieDistributorTask = self

	self.AppraiseMovies = JobAppraiseMovies()
	self.AppraiseMovies.MovieDistributorTask = self

	self.BuyMovies = JobBuyMovies()
	self.BuyMovies.MovieDistributorTask = self
	
	self.BidAuctions = JobBidAuctions()
	self.BidAuctions.MovieDistributorTask = self

	self.MoviesAtDistributor = {}
	self.MoviesAtAuctioneer = {}


	local player = _G["globalPlayer"]
	debugMsg("    Task information: CurrentBudget=" .. self.CurrentBudget .. "  CurrentBargainBudget=" .. self.CurrentBargainBudget .. "  ProgrammesPossessed=" .. self.ProgrammesPossessed .. "  startProgrammeAmount=" .. player.Strategy.startProgrammeAmount)

	--added entry for movie selling 
	self.SellSuitcaseLicences = JobSellSuitcaseLicences()
	self.SellSuitcaseLicences.MovieDistributorTask = self
end


function TaskMovieDistributor:GetNextJobInTargetRoom()
	--added entry for programme licence selling, needs to come first
	--add "existence check" to skip errors in older savegames not knowing
	--the new job
	if (self.SellSuitcaseLicences ~= nil and self.SellSuitcaseLicences.Status ~= JOB_STATUS_DONE) then
		return self.SellSuitcaseLicences
	elseif (self.BuyStartProgrammeJob.Status ~= JOB_STATUS_DONE) then
		return self.BuyStartProgrammeJob
	elseif (self.BuyRequisitedLicencesJob.Status ~= JOB_STATUS_DONE) then
		return self.BuyRequisitedLicencesJob

	-- Check for "nice to have" licences
	elseif (self.CheckMoviesJob.Status ~= JOB_STATUS_DONE) then
		return self.CheckMoviesJob
	elseif (self.AppraiseMovies.Status ~= JOB_STATUS_DONE) then
		return self.AppraiseMovies
	elseif (self.BuyMovies.Status ~= JOB_STATUS_DONE) then
		return self.BuyMovies
	elseif (self.BidAuctions.Status ~= JOB_STATUS_DONE) then
		return self.BidAuctions		
	end

	--self:SetWait()
	self:SetDone()
end


function TaskMovieDistributor:getStrategicPriority()
	--debugMsg("TaskMovieDistributor:getStrategicPriority")

	-- no money to buy things? skip even looking...
	if TVT.getMoney() <= 0 then
		return 0.0
	end
	return 1.0
end


function TaskMovieDistributor:BudgetSetup()
	-- Tagesbudget für gute Angebote ohne konkreten Bedarf
	self.CurrentBargainBudget = self.BudgetWholeDay / 2
end

function TaskMovieDistributor:OnMoneyChanged(value, reason, reference)
	if (tostring(reason) == tostring(TVT.Constants.PlayerFinanceEntryType.PAY_PROGRAMMELICENCE)) then
		--self:PayFromBudget(value)
		--self.CurrentBargainBudget = self.CurrentBargainBudget - value
	elseif (tostring(reason) == tostring(TVT.Constants.PlayerFinanceEntryType.SELL_PROGRAMMELICENCE)) then
		--Wird im Budgetmanager neu verteilt
	elseif (tostring(reason) == tostring(TVT.Constants.PlayerFinanceEntryType.PAY_AUCTIONBID)) then
		--self:PayFromBudget(value)	Wird unten gemacht, damit der Kontostand gleich aktuell ist. Muss man mal Debuggen
	elseif (tostring(reason) == tostring(TVT.Constants.PlayerFinanceEntryType.PAYBACK_AUCTIONBID)) then
		self.CurrentBudget = self.CurrentBudget + value -- Zurück zahlen
	end
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
_G["JobBuyStartProgramme"] = class(AIJob, function(c)
	AIJob.init(c)	-- must init base!
	c.CurrentMovieIndex = 0
	c.MovieDistributorTask = nil
	c.AllMoviesChecked = false
end)

function JobBuyStartProgramme:typename()
	return "JobBuyStartProgramme"
end

function JobBuyStartProgramme:Prepare(pParams)
	--debugMsg("Schaue Filmangebot an")
	self.CurrentMovieIndex = 0
end

function JobBuyStartProgramme:Tick()
	local player = _G["globalPlayer"]
	
	--try to buy at least 4-x cheap start programmes
	local start
	local moviesNeeded = player.Strategy.startProgrammeAmount - (TVT.Rules.startProgrammeAmount + self.MovieDistributorTask.ProgrammesPossessed)
	if moviesNeeded <= 0 then
		self.Status = JOB_STATUS_DONE
		return True
	end
	
	local licencesResponse = TVT.md_getProgrammeLicences()
	if ((licencesResponse.result == TVT.RESULT_WRONGROOM) or (licencesResponse.result == TVT.RESULT_NOTFOUND)) then
		self.Status = JOB_STATUS_DONE
		return True
	end


	-- budget is based on needed*price, so if we find cheaper programmes
	-- we might buy more than needed
	local startMovieBudget = player.Strategy.startProgrammePriceMax
	local startMovieBudgetMax = 2 * startMovieBudget
	local startMoviesBudget = player.Strategy.startProgrammeBudget
		

	local movies = TVT.convertToProgrammeLicences(licencesResponse.data)	
	local goodMovies = {}
	-- sort lowest first
	local sortByPrice = function(a, b)
		return a:GetPrice(TVT.ME) < b:GetPrice(TVT.ME)
	end

	-- add "okay" movies to the list of candidates
	for k,v in pairs(movies) do
		--avoid the absolute trash :-)
		if (v:GetQuality() >= 0.10 and v:GetPrice(TVT.ME) <= startMovieBudgetMax) then
			table.insert(goodMovies, v)
		end
	end
	table.sort(goodMovies, sortByPrice)

	
	local buyStartMovies = {}
	for k,v in pairs(goodMovies) do
		-- stop iteration if getting low on budget
		if startMoviesBudget < v.GetPrice(TVT.ME) then break end 
		-- a single licence could be more expensive than the average budget
		if v.GetPrice(TVT.ME) <= startMovieBudgetMax then
			table.insert(buyStartMovies, v)
			startMoviesBudget = startMoviesBudget - v.GetPrice(TVT.ME)
		end
	end

	for k,v in pairs(buyStartMovies) do
		--only buy whole start programme set if possible with budget
		--else each one should be cheaper than the single licence limit
		if (table.count(buyStartMovies) >= moviesNeeded or v.GetPrice(TVT.ME) < startMovieBudget) then
			debugMsg("Buying start programme licence: " .. v.GetTitle() .. " (" .. v.GetId() .. ") - Price: " .. v:GetPrice(TVT.ME))
			TVT.md_doBuyProgrammeLicence(v.GetId())

			--attention: we subtract from the overall "buying programme"
			--           budget!
			self.MovieDistributorTask:PayFromBudget(v:GetPrice(TVT.ME))
			self.MovieDistributorTask.CurrentBargainBudget = self.MovieDistributorTask.CurrentBargainBudget - v:GetPrice(TVT.ME)							

			--increase counter to skip buying more
			self.MovieDistributorTask.ProgrammesPossessed = self.MovieDistributorTask.ProgrammesPossessed + 1
		end
	end
	
	self.Status = JOB_STATUS_DONE
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<




-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
_G["JobBuyRequisitedLicences"] = class(AIJob, function(c)
	AIJob.init(c)	-- must init base!
	c.Id = c.typename()
	c.MovieDistributorTask = nil
end)

function JobBuyRequisitedLicences:typename()
	return "JobBuyStartProgramme"
end

function JobBuyRequisitedLicences:Prepare(pParams)
	self.Player = _G["globalPlayer"]
end

function JobBuyRequisitedLicences:Tick()
	local player = _G["globalPlayer"]

	-- try to fulfill the requisitions

	-- fetch all (also outdated) requisitions
	local buyLicencesRequisitions = self.Player:GetRequisitionsByTaskId(_G["TASK_MOVIEDISTRIBUTOR"], true)
	-- fetch all available licences
	local licencesResponse = TVT.md_getProgrammeLicences()
	if ((licencesResponse.result == TVT.RESULT_WRONGROOM) or (licencesResponse.result == TVT.RESULT_NOTFOUND)) then
		self.Status = JOB_STATUS_DONE
		return True
	end
	local availableLicences = TVT.convertToProgrammeLicences(licencesResponse.data)	


	-- sort by attractivity/price
	local sortByAttractivity = function(a, b)
		return a.GetQuality() * a.GetPrice(TVT.ME) < b.GetQuality() * b.GetPrice(TVT.ME)
	end


	for k,buyLicencesReq in pairs(buyLicencesRequisitions) do
		-- loop over all buy-licences-requisitions (which each could
		-- contain multiple entries)
		if buyLicencesReq.requisitionID ~= nil and buyLicencesReq.requisitionID == "BuyProgrammeLicencesRequisition" then
			-- delete old ones (also removes in-actual singleLicenceReqs)
			if not buyLicencesReq:CheckActuality() then
debugMsg("JobBuyRequisitedLicences:Tick() - buyLicencesReq outdated")
				player:RemoveRequisition(buyLicencesReq)

			-- process others
			else
				--- loop over all single licence requisitions in the group
				for buySingleLicenceReqKey, buySingleLicenceReq in pairs(buyLicencesReq.licenceReqs) do
					-- collect fitting licences
					local relevantLicences = {}
					for licenceKey, licence in pairs(availableLicences) do
						local valid = true
						local price = licence.GetPrice(TVT.ME)
						if licence:GetPrice(TVT.ME) < buySingleLicenceReq.minPrice then valid = false; end
						if licence:GetPrice(TVT.ME) > buySingleLicenceReq.maxPrice and buySingleLicenceReq.maxPrice > 0 then valid = false; end

						if valid then
							table.insert(relevantLicences, licence)
						end
					end
					-- sort by quality/price
					table.sort(relevantLicences, sortByAttractivity)

					-- buy best one
					local licence = table.first(relevantLicences)
					if licence ~= nil then
						if TVT.md_doBuyProgrammeLicence(licence.GetId()) == TVT.RESULT_OK then
							debugMsg("Bought requisition programme licence: " .. licence.GetTitle() .. " (" .. licence.GetId() .. ") - Price: " .. licence:GetPrice(TVT.ME))
							buySingleLicenceReq:Complete()
						else
							debugMsg("Buying requisition programme licence FAILED: " .. licence.GetTitle() .. " (" .. licence.GetId() .. ") - Price: " .. licence:GetPrice(TVT.ME))
						end
					end
				end
			end
		end
	end


	self.Status = JOB_STATUS_DONE
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<




-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
_G["JobCheckMovies"] = class(AIJob, function(c)
	AIJob.init(c)	-- must init base!
	c.CurrentMovieIndex = 0
	c.CurrentAuctionIndex = 0
	c.MovieDistributorTask = nil
	c.AllMoviesChecked = false
	c.AllAuctionsChecked = false
end)

function JobCheckMovies:typename()
	return "JobCheckMovies"
end

function JobCheckMovies:Prepare(pParams)
	--debugMsg("Schaue Filmangebot an")
	self.CurrentMovieIndex = 0
end

function JobCheckMovies:Tick()
	while self.Status ~= JOB_STATUS_DONE and not self.AllMoviesChecked do
		self:CheckMovie()		
	end
	
	while self.Status ~= JOB_STATUS_DONE and not self.AllAuctionsChecked do
		self:CheckAuction()
	end		

	self.Status = JOB_STATUS_DONE
end

function JobCheckMovies:CheckMovie()
	local response = TVT.md_getProgrammeLicence(self.CurrentMovieIndex)
	if ((response.result == TVT.RESULT_WRONGROOM) or (response.result == TVT.RESULT_NOTFOUND)) then
		self.AllMoviesChecked = true
		return
	end

	local licence = TVT.convertToProgrammeLicence(response.data)	
	self.MovieDistributorTask.MoviesAtDistributor[self.CurrentMovieIndex] = licence

	local player = _G["globalPlayer"]
	player.Stats:AddMovie(licence)

	self.CurrentMovieIndex = self.CurrentMovieIndex + 1
end

function JobCheckMovies:CheckAuction()
	local response = TVT.md_getAuctionProgrammeLicence(self.CurrentAuctionIndex)
	if ((response.result == TVT.RESULT_WRONGROOM) or (response.result == TVT.RESULT_NOTFOUND)) then
		self.AllAuctionsChecked = true
		return
	end

	local licence = TVT.convertToProgrammeLicence(response.data)
	self.MovieDistributorTask.MoviesAtAuctioneer[self.CurrentAuctionIndex] = licence
	self.CurrentAuctionIndex = self.CurrentAuctionIndex + 1
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
_G["JobAppraiseMovies"] = class(AIJob, function(c)
	AIJob.init(c)	-- must init base!
	c.CurrentMovieIndex = 0
	c.CurrentAuctionIndex = 0
	c.MovieDistributorTask = nil

	c.MovieMaxPrice = -1
	c.PrimetimeMovieMinQuality = -1
	c.DayMovieMinQuality = -1

	c.SeriesMaxPrice = -1
	c.PrimetimeSeriesMinQuality = -1
	c.DaySeriesMinQuality = -1
	
	c.AllMoviesChecked = false
	c.AllAuctionsChecked = false	
end)

function JobAppraiseMovies:typename()
	return "JobAppraiseMovies"
end

function JobAppraiseMovies:Prepare(pParams)
	--debugMsg("Bewerte/Vergleiche Filme")
	self.CurrentMovieIndex = 0
	self.CurrentAuctionIndex = 0
	self:AdjustMovieNiveau()
end

function JobAppraiseMovies:Tick()
	while self.Status ~= JOB_STATUS_DONE and not self.AllMoviesChecked do
		self:AppraiseCurrentMovie()
	end
	
	while self.Status ~= JOB_STATUS_DONE and not self.AllAuctionsChecked do
		self:AppraiseCurrentAuction()
	end
	
	self.Status = JOB_STATUS_DONE
end


function JobAppraiseMovies:AdjustMovieNiveau()
	local player = _G["globalPlayer"]
	local stats = player.Stats
	local movieBudget = self.MovieDistributorTask.BudgetWholeDay

	local maxQualityMovies = stats.MovieQualityAcceptable.MaxValue
	local minQualityMovies = stats.MovieQualityAcceptable.MinValue
	local maxQualitySeries = stats.SeriesQualityAcceptable.MaxValue
	local minQualitySeries = stats.SeriesQualityAcceptable.MinValue

	self.MovieMaxPrice = movieBudget * 0.75
	self.SeriesMaxPrice = movieBudget * 0.9

	local ScopeMovies = maxQualityMovies - minQualityMovies
	self.PrimetimeMovieMinQuality = math.round(minQualityMovies + (ScopeMovies * 0.75))
	self.DayMovieMinQuality = math.round(minQualityMovies + (ScopeMovies * 0.4))

	local ScopeSeries = maxQualitySeries - minQualitySeries
	self.PrimetimeSeriesMinQuality = math.round(minQualitySeries + (ScopeSeries * 0.75))
	self.DaySeriesMinQuality = math.round(minQualitySeries + (ScopeSeries * 0.4))

	debugMsg("Adjusted movies niveau:  MovieMaxPrice=" .. math.floor(self.MovieMaxPrice) .."  PrimetimeMovieMinQuality=" .. self.PrimetimeMovieMinQuality .. "  DayMovieMinQuality=" .. self.DayMovieMinQuality)
	debugMsg("         series niveau:  SeriesMaxPrice=" .. math.floor(self.SeriesMaxPrice) .."  PrimetimeSeriesMinQuality=" .. self.PrimetimeSeriesMinQuality .. "  DaySeriesMinQuality=" .. self.DaySeriesMinQuality)
end


function JobAppraiseMovies:AppraiseCurrentMovie()
	--debugMsg("AppraiseCurrentMovie #" .. self.CurrentMovieIndex)
	local movie = self.MovieDistributorTask.MoviesAtDistributor[self.CurrentMovieIndex]
	if (movie ~= nil) then
		self:AppraiseMovie(movie)
		self.CurrentMovieIndex = self.CurrentMovieIndex + 1
	else
		self.AllMoviesChecked = true
	end
end


function JobAppraiseMovies:AppraiseCurrentAuction()
	local movie = self.MovieDistributorTask.MoviesAtAuctioneer[self.CurrentAuctionIndex]
	if (movie ~= nil) then
		self:AppraiseMovie(movie)
		self.CurrentAuctionIndex = self.CurrentAuctionIndex + 1
	else
		self.AllAuctionsChecked = true
	end
end


-- sets attractiveness of licences ... if fitting
function JobAppraiseMovies:AppraiseMovie(licence)
	--debugMsg("  AppraiseMovie \"" .. licence.GetTitle() .. "\"")
	local player = _G["globalPlayer"]
	local stats = player.Stats
	local pricePerBlockStats = nil
	local qualityStats = nil

	-- reset attractiveness, if it fits to the CURRENT conditions, it
	-- gets updated accordingly
	licence.SetAttractiveness(0)

	-- satisfied basic requirements?
	if (licence.IsSingle() == 1) then
		if (CheckMovieBuyConditions(licence, self.MovieMaxPrice, self.DayMovieMinQuality)) then
			pricePerBlockStats = stats.MoviePricePerBlockAcceptable
			qualityStats = stats.MovieQualityAcceptable
		else
			return
		end
	else
		if (CheckMovieBuyConditions(licence, self.SeriesMaxPrice, self.DaySeriesMinQuality)) then
			pricePerBlockStats = stats.SeriesPricePerBlockAcceptable
			qualityStats = stats.SeriesQualityAcceptable
		else
			return
		end
	end

	-- the cheaper the better
	local financeFactor = licence:GetPricePerBlock() / pricePerBlockStats.AverageValue
	financeFactor = CutFactor(financeFactor, 0.2, 2)
	--debugMsg("licence: GetPricePerBlock=" .. licence.GetPricePerBlock() .. "  pricePerBlockStats.AverageValue=" .. pricePerBlockStats.AverageValue)

	-- the higher the quality the better
	local qualityFactor = licence.GetQuality() / qualityStats.AverageValue
	qualityFactor = CutFactor(qualityFactor, 0.2, 2)
	--debugMsg("licence: Quality=" .. licence.GetQuality() .. "  qualityStats.AverageValue=" .. qualityStats.AverageValue)

	licence.SetAttractiveness(financeFactor * qualityFactor)
	--debugMsg("Licence: Attractiveness=" .. licence.GetAttractiveness() .. "  financeFactor=" .. financeFactor .. "  qualityFactor=" .. qualityFactor)
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
_G["JobBuyMovies"] = class(AIJob, function(c)
	AIJob.init(c)	-- must init base!
	c.MovieDistributorTask = nil
end)

function JobBuyMovies:typename()
	return "JobBuyMovies"
end

function JobBuyMovies:Prepare(pParams)
	--debugMsg("Buying Programme licences")
	if (self.MovieDistributorTask.MoviesAtDistributor ~= nil) then
		local sortMethod = function(a, b)
			return a.GetAttractiveness() > b.GetAttractiveness()
		end
		table.sort(self.MovieDistributorTask.MoviesAtDistributor, sortMethod)
	end
end

function JobBuyMovies:Tick()
	local movies = self.MovieDistributorTask.MoviesAtDistributor

	if (movies ~= nil) then
		for k,v in pairs(movies) do		
			if (v:GetPrice(TVT.ME) <= self.MovieDistributorTask.CurrentBudget) then
				-- daily budget for good offers without direct need
				if v:GetPrice(TVT.ME) <= self.MovieDistributorTask.CurrentBargainBudget then
					if (v.GetAttractiveness() > 1) then
						debugMsg("Buying licence: " .. v.GetTitle() .. " (" .. v.GetId() .. ") - Price: " .. v:GetPrice(TVT.ME))
						TVT.md_doBuyProgrammeLicence(v.GetId())
						
						self.MovieDistributorTask:PayFromBudget(v:GetPrice(TVT.ME))
						self.MovieDistributorTask.CurrentBargainBudget = self.MovieDistributorTask.CurrentBargainBudget - v:GetPrice(TVT.ME)							

						--increase counter to skip buying more "needed ones"
						self.MovieDistributorTask.ProgrammesPossessed = self.MovieDistributorTask.ProgrammesPossessed + 1
					end			
				end
			end
		end
	else
		TVT.addToLog("Movieagency does not offer any licences.")
	end

	self.Status = JOB_STATUS_DONE
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
_G["JobBidAuctions"] = class(AIJob, function(c)
	AIJob.init(c)	-- must init base!
	c.MovieDistributorTask = nil
end)

function JobBidAuctions:typename()
	return "JobBuyMovies"
end

function JobBidAuctions:Prepare(pParams)
	--debugMsg("Biete auf Auktionen")

	local sortMethod = function(a, b)
		return a.GetAttractiveness() > b.GetAttractiveness()
	end
	table.sort(self.MovieDistributorTask.MoviesAtAuctioneer, sortMethod)
end

function JobBidAuctions:Tick()
	local movies = self.MovieDistributorTask.MoviesAtAuctioneer

	--TODO: Prüfen wie viele Filme überhaupt gebraucht werden

	for k,v in pairs(movies) do
		if (v:GetPrice(TVT.ME) <= self.MovieDistributorTask.CurrentBudget) then
			if (v:GetPrice(TVT.ME) <= self.MovieDistributorTask.CurrentBargainBudget) then -- Tagesbudget für gute Angebote ohne konkreten Bedarf				
				if (v.GetAttractiveness() > 1) then
					--debugMsg("Kaufe Film: " .. v.GetId() .. " - Attraktivität: ".. v.GetAttractiveness() .. " - Preis: " .. v:GetPrice(TVT.ME) .. " - Qualität: " .. v.GetQuality(0))
					debugMsg("[Licence auction] placing bet for: " .. v.GetTitle() .. " (" .. v.GetId() .. ") - Price: " .. v:GetPrice(TVT.ME) .." - Attractivity: " .. v:GetAttractiveness())
					TVT.md_doBidAuctionProgrammeLicence(v.GetId())
					
					self.MovieDistributorTask:PayFromBudget(v:GetPrice(TVT.ME))
					self.MovieDistributorTask.CurrentBargainBudget = self.MovieDistributorTask.CurrentBargainBudget - v:GetPrice(TVT.ME)
				else
					debugMsg("[Licence auction] too low attractivity: " .. v.GetTitle() .. " (" .. v.GetId() .. ") - Price: " .. v:GetPrice(TVT.ME) .." - Attractivity: " .. v:GetAttractiveness())
				end
			end
		end
	end

	self.Status = JOB_STATUS_DONE
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<



-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
_G["JobSellSuitcaseLicences"] = class(AIJob, function(c)
	AIJob.init(c)	-- must init base!
	c.MovieDistributorTask = nil	
end)


function JobSellSuitcaseLicences:typename()
	return "JobSellSuitcaseLicences"
end


function JobSellSuitcaseLicences:Prepare(pParams)

end


function JobSellSuitcaseLicences:Tick()
	--sell content of suitcase
	debugMsg("JobSellLicences Tick")
	local myPC = MY.GetProgrammeCollection()
	local nCase = myPC.GetSuitcaseProgrammeLicenceCount()
	local case = myPC.GetSuitcaseProgrammeLicencesArray()
	debugMsg("md case has: "..#case)

	--for i=1, #case do debugMsg("md case "..i.." : "..tostring(case[i])) end
	if case ~= nil and #case > 0 then
		--debugMsg("attempt sale")
		for i=1,#case 
		do
			local v = case[i]
			if v ~= nil 
			then 
				err = TVT.md_doSellProgrammeLicence(v.GetId()) 
				debugMsg("sold "..v.GetTitle().." id "..v.GetId().." with error code: "..err)
			else debugMsg("md sale: nil value")	end
		end
	else debugMsg ("md: empty suitcase") end

	self.Status = JOB_STATUS_DONE
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
