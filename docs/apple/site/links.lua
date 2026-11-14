-- Rewrites the links and images of a page for the website (ADR-0067).
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
  -- Another file of the site, such as an image, by its path in the site, also from the manual.
  local inside = file:match("^docs/apple/site/(.+)$")
  if inside then
    return inside
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

-- A screenshot in light, `<name>-light.webp`, has a copy in dark beside it, which `make screenshots` takes too; the
-- page shows both, and style.css the one of the colour scheme. GitHub shows the light one.
local function dark_copy(src)
  local dark, found = src:gsub("%-light%.webp$", "-dark.webp")
  return found > 0 and dark or nil
end

function Image(image)
  local dark = dark_copy(image.src)
  image.src = rewrite(image.src)
  if not dark then
    return image
  end
  local copy = image:clone()
  copy.src = rewrite(dark)
  image.classes:insert("light")
  copy.classes:insert("dark")
  return { image, copy }
end

-- The manual sets the width of its images in HTML, which GitHub keeps: each <img> as an image of Markdown.
local function html_images(text)
  return (text:gsub("<img%s[^>]*>", function(tag)
    local src = tag:match('src="([^"]+)"')
    if not src then
      return tag
    end
    local function with(path, class)
      local result = tag:gsub('src="[^"]+"', function() return 'src="' .. rewrite(path) .. '"' end, 1)
      if class then
        result = result:gsub("^<img", '<img class="' .. class .. '"', 1)
      end
      return result
    end
    local dark = dark_copy(src)
    if not dark then
      return with(src)
    end
    return with(src, "light") .. with(dark, "dark")
  end))
end

function RawInline(raw)
  if raw.format == "html" then
    raw.text = html_images(raw.text)
  end
  return raw
end

function RawBlock(raw)
  if raw.format == "html" then
    raw.text = html_images(raw.text)
  end
  return raw
end

-- The filter reads the metadata before it rewrites the links.
return { { Meta = Meta }, { Link = Link, Image = Image, RawInline = RawInline, RawBlock = RawBlock } }
