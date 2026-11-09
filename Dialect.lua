local _, ns = ...
local speak = ns.speak

-- The dialect engine: pure text in, mangled text out. Dictionaries.lua
-- holds the tables; array order there is match order here. The only
-- impure input is math.random (variant picks and chance rolls), which
-- the client seeds itself -- this package never reseeds shared
-- randomness -- so headless tests stub it for deterministic lines.

-- A trailing "!" marks a flavor replacement: it applies only when a
-- 1-100 roll stays under chance * 10. Unmarked replacements always
-- apply. Markers strip either way, so stored text never leaks out.
speak.FLAVOR_MARK = "!"

-- The one impure input, defaulting to the shared generator. Tests
-- replace it per speak table for deterministic lines; the package
-- never reseeds shared randomness.
speak.random = math.random

-- One variant from an entry: a plain string returns itself, a table
-- of variants returns one at random.
function speak.PickVariant(entry)
  if type(entry) == "table" then
    if #entry == 0 then
      return nil
    end
    return entry[speak.random(#entry)]
  end
  return entry
end

-- Memoized string surgery for the hot path. Dictionary tables persist
-- for the session and keys are dictionary strings only, so each
-- distinct string pays construction once. Bounded, never user chat.
local strippedCache = {}
local capCache = {}

-- Strip the flavor marker, memoized: the same replacement text
-- always strips to the same output.
local function stripFlavor(replacement)
  local stripped = strippedCache[replacement]
  if stripped == nil then
    stripped = replacement:gsub("[" .. speak.FLAVOR_MARK .. "]+%s*$", "")
    strippedCache[replacement] = stripped
  end
  return stripped
end

-- Capitalized match/replace forms, memoized per search+replacement.
-- A leading character class or capture has no literal first letter
-- to uppercase, so the textual derivation is skipped for those
-- (the lowercase pass already covers them, e.g. Running->Runnin').
local function capForms(search, replace)
  local key = search .. "\0" .. replace
  local hit = capCache[key]
  if hit == nil then
    hit = {}
    if search:gsub("^%^", ""):sub(1, 1):find("%l") then
      hit.searchCap = search:gsub("%l", string.upper, 1)
      hit.replaceCap = replace:gsub("%l", string.upper, 1)
    end
    capCache[key] = hit
  end
  return hit.searchCap, hit.replaceCap
end

-- Roll one picked replacement against the chance. Flavor thins out
-- below chance 10; at 10 everything applies. Returns nil when the
-- replacement sits this message out.
function speak.Decide(replacement, chance)
  if type(replacement) ~= "string" then
    return nil
  end
  if chance < 10 and replacement:sub(-1) == speak.FLAVOR_MARK and speak.random(100) > chance * 10 then
    return nil
  end
  return stripFlavor(replacement)
end

-- Rewrite one segment with one pair. All-caps stays untouched, so
-- shouting never comes out mangled. Otherwise the lowercase pattern
-- applies, then the capitalized variant -- except the ^he rule, whose
-- capitalized form would mangle "'E" out of "He".
function speak.TranslateSegment(segment, search, replace)
  if segment:find("^[%u]+$") then
    return segment
  end
  segment = segment:gsub(search, replace)
  -- No uppercase, no capitalized match: the derived form always
  -- carries an uppercase letter the segment cannot contain.
  if search ~= "^he" and segment:find("%u") then
    local searchCap, replaceCap = capForms(search, replace)
    if searchCap then
      segment = segment:gsub(searchCap, replaceCap)
    end
  end
  return segment
end

-- Mangle one chat line with one dialect table. Hyperlinks shelter
-- behind control-char placeholders first (non-greedy: the 2007 greedy
-- match could swallow two links and the text between them) and come
-- back byte-identical through a function replacement, so a "%" in a
-- link can never read as a capture. Phrases need surrounding spaces,
-- like the original; words split on whitespace with trailing
-- punctuation carried through. A "^"-anchored rule skips a word that
-- follows an apostrophe ending, so "'e ol'" never doubles up.
function speak.Mangle(text, dict, chance)
  if type(text) ~= "string" or type(dict) ~= "table" then
    return text
  end
  local sheltered = {}
  local protected = text:gsub("(|c.-|r)", function(link)
    sheltered[#sheltered + 1] = link
    return "\1" .. #sheltered .. "\1"
  end)
  if type(dict.dict1) == "table" then
    for _, pair in ipairs(dict.dict1) do
      local replace = speak.Decide(speak.PickVariant(pair[2]), chance)
      if replace ~= nil then
        protected = speak.TranslateSegment(protected, "%s+" .. pair[1] .. "%s+", " " .. replace .. " ")
      end
    end
  end
  local out, last = {}, ""
  if type(dict.dict2) == "table" then
    for segment in protected:gmatch("%S+") do
      local tail = segment:match("(%p+)$") or ""
      local core = segment:gsub("%p*$", "")
      for _, pair in ipairs(dict.dict2) do
        local search = pair[1]
        if not (search:sub(1, 1) == "^" and last:sub(-1) == "'") then
          local replace = speak.Decide(speak.PickVariant(pair[2]), chance)
          if replace ~= nil then
            core = speak.TranslateSegment(core, search, replace)
          end
        end
      end
      core = core:gsub("''", "'")
      last = core
      out[#out + 1] = core .. tail
    end
  end
  local message = table.concat(out, " ")
  message = message:gsub("\1(%d+)\1", function(index)
    return sheltered[tonumber(index)]
  end)
  return message
end
