-- Rewrites the links of a page for the website (ADR-0067).
-- A link to a document that is a page of the site (faq.md, manual.md, CHANGELOG.md, ...) points to its .html page. Any other
-- relative link points to the file on GitHub, so that the Markdown files keep working there unchanged.
-- Metadata: `srcdir`, the repository-relative folder of the source file, and `repo`, the repository's GitHub URL.

local pages = {
  ["docs/apple/faq.md"] = "faq.html",
  ["docs/apple/manual.md"] = "manual.html",
  ["apple-src/App/KV4PHT/CHANGELOG.md"] = "changelog.html",
}
local srcdir, repo
local values = {}

-- Resolves `path` against `dir`, both repository-relative, removing `.` and `..`.
local function resolve(dir, path)
  local parts = {}
  for part in (dir .. "/" .. path):gmatch("[^/]+") do
    if part == ".." then
      table.remove(parts)
    elseif part ~= "." then
      table.insert(parts, part)
    end
  end
  return table.concat(parts, "/")
end

local function rewrite(target)
  -- A target starting with `$name$` starts with a value of site.yaml, such as `$testflight$` or `$repo$/issues`.
  local key, rest = target:match("^%$([%w-]+)%$(.*)$")
  if key and values[key] then
    return values[key] .. rest
  end
  if target:match("^%a[%w+.-]*:") or target:match("^#") or target == "" then
    return target
  end
  local path, fragment = target:match("^([^#]*)(#?.*)$")
  local file = resolve(srcdir, path)
  if pages[file] then
    return pages[file] .. fragment
  end
  -- The pages written for the site become their .html page, and its other files stay as they are.
  local own = file:match("^docs/apple/site/([^/]+)%.md$")
  if own then
    return own .. ".html" .. fragment
  end
  if file:match("^docs/apple/site/") then
    return target
  end
  local kind = path:match("/$") and "tree" or "blob"
  return repo .. "/" .. kind .. "/main/" .. file .. fragment
end

function Meta(meta)
  for key, value in pairs(meta) do
    values[key] = pandoc.utils.stringify(value)
  end
  srcdir = values.srcdir
  repo = values.repo
end

function Link(link)
  link.target = rewrite(link.target)
  return link
end

-- The filter reads the metadata before it rewrites the links.
return { { Meta = Meta }, { Link = Link } }
