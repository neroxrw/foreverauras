-- Modified for ForeverAuras; namespace and/or implementation changes through 2026-09-18.
if not ForeverAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)

---@class ForeverAuras
local ForeverAuras = ForeverAuras

local histRepo, migrationRepo
local function loadHistory()
  if not histRepo then
    histRepo = ForeverAuras.LoadFromArchive("Repository", "history")
  end
  return histRepo
end

local function loadMigrations()
  if not migrationRepo then
    migrationRepo = ForeverAuras.LoadFromArchive("Repository", "migration")
  end
  return migrationRepo
end

function Private.CleanArchive(historyCutoff, migrationCutoff)
  if type(historyCutoff) == "number" then
    local repo = loadHistory()
    local cutoffTime = time() - (historyCutoff * 86400)
    for uid, subStore in pairs(repo.stores) do
      -- Ideally we would just use Clean and not access the stores list directly,
      -- but that'd mean having Clean take a predicate which seems like overkill for the moment
      if not Private.GetDataByUID(uid) and subStore.timestamp < cutoffTime then
        repo:Drop(uid)
      end
    end
  end

  if type(migrationCutoff) == "number" then
    local repo = loadMigrations()
    repo:Clean(time() - (migrationCutoff * 86400))
  end
end

function Private.SetHistory(uid, data, source)
  if uid and data then
    local repo = loadHistory()
    data.source = source
    local hist = repo:Set(uid, data, true)
    return hist
  end
end

local function GetHistory(uid, load)
  return loadHistory():Get(uid, load)
end

function Private.RemoveHistory(uid)
  return loadHistory():Drop(uid)
end

function Private.RestoreFromHistory(uid)
  local _, histData = GetHistory(uid, true)
  if histData then
    ForeverAuras.Add(histData)
  end
end

function Private.SetMigrationSnapshot(uid, oldData)
  if type(oldData) == "table" then
    local repo = loadMigrations()
    repo:Set(uid, oldData)
  end
end

function Private.GetMigrationSnapshot(uid)
  return loadMigrations():GetData(uid)
end
