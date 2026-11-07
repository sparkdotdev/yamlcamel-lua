package = "yamlcamel-lua"
version = "scm-1"

source = {
  url = "git+https://github.com/sparkdotdev/yamlcamel-lua.git",
  branch = "main",
}

description = {
  summary = "A pure-Lua reader and writer for a small subset of YAML",
  detailed = [[
Parses and encodes mappings, sequences and scalars, in block and flow style,
including block scalars, multi-line flow collections, anchors and aliases,
multi-document streams, and explicit tags. See the README for what of YAML
1.2.2 is and is not covered yet.

No C extension and no dependency outside the Lua standard library, so it
installs and runs anywhere a plain Lua interpreter does, sandboxed embeds
included. File, gzip and HTTP convenience I/O sit behind pluggable
interfaces (yamlcamel.io.*) with optional default implementations; see the
README for the extra rocks those defaults need and how to swap in your own.
  ]],
  homepage = "https://github.com/sparkdotdev/yamlcamel-lua",
  license = "PolyForm-Noncommercial-1.0.0 OR PolyForm-Small-Business-1.0.0",
}

-- The default HTTP transport (`http`) and gzip compressor (`lua-zlib`) are deliberately not
-- listed here: both are required lazily by their own default implementations, so skipping HTTP
-- or gzip, or injecting a custom transport, never needs them installed. See the README.
dependencies = {
  "lua >= 5.4",
}

build = {
  type = "builtin",
  modules = {
    ["yamlcamel"] = "src/yamlcamel/init.lua",
    ["yamlcamel.parser"] = "src/yamlcamel/parser.lua",
    ["yamlcamel.emitter"] = "src/yamlcamel/emitter.lua",
    ["yamlcamel.flow"] = "src/yamlcamel/flow.lua",
    ["yamlcamel.quoted"] = "src/yamlcamel/quoted.lua",
    ["yamlcamel.scalar"] = "src/yamlcamel/scalar.lua",
    ["yamlcamel.null"] = "src/yamlcamel/null.lua",
    ["yamlcamel.anchors"] = "src/yamlcamel/anchors.lua",
    ["yamlcamel.props"] = "src/yamlcamel/props.lua",
    ["yamlcamel.tags"] = "src/yamlcamel/tags.lua",
    ["yamlcamel.limits"] = "src/yamlcamel/limits.lua",
    ["yamlcamel.charset"] = "src/yamlcamel/charset.lua",
    ["yamlcamel.whitespace"] = "src/yamlcamel/whitespace.lua",
    ["yamlcamel.gzip"] = "src/yamlcamel/gzip.lua",
    ["yamlcamel.http"] = "src/yamlcamel/http.lua",
    ["yamlcamel.stream"] = "src/yamlcamel/stream.lua",
    ["yamlcamel.io.file"] = "src/yamlcamel/io/file.lua",
    ["yamlcamel.io.compression"] = "src/yamlcamel/io/compression.lua",
    ["yamlcamel.io.transport"] = "src/yamlcamel/io/transport.lua",
  },
}
