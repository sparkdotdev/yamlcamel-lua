# YAMLCamel for Lua

YAMLCamel reads and writes YAML using Lua source files. It supports mappings, sequences, scalars and document streams without a native parser extension. Optional file, gzip and HTTP helpers can use either the supplied implementations or ones provided by your host.

Copyright 2026, Spark Software Development, LLC.

## Features

Call `yamlcamel.decode` to read one document and `yamlcamel.encode` to write a Lua value. Tables represent mappings and sequences; `yamlcamel.null` keeps an explicit YAML null distinct from an absent Lua field, and `yamlcamel.EMPTY_MAPPING` writes an empty mapping instead of an empty sequence.

The parser follows [YAML 1.2.2](https://yaml.org/spec/1.2.2/) core scalar rules and supports block and flow collections, quoted strings, block scalars, anchors, aliases, and explicit tags. Unknown tags are kept in wrappers you can inspect. The syntax support is a subset of the specification. Encoding writes fresh YAML and drops the original comments and formatting.

Use `decode_all` and `encode_all` for a complete document stream. `decode_file_stream` calls back once per document so a multi-document file does not need to be held in memory as one string. It streams documents, not the individual elements of one large sequence.

File access, gzip compression and HTTP transport are replaceable. The parser and emitter need only Lua, which makes them easy to embed without installing extra rocks. The default gzip and network helpers load their extra rocks when used. Nesting, emission and transfer limits bound several kinds of input and output work.

## Configuration

There is no environment-file configuration. Configure the relevant operation through its options table, or supply host implementations for the I/O interfaces.

| Option or value | Purpose |
| --- | --- |
| `opts.file` | Replace file access. |
| `opts.compression` | Replace gzip compression and decompression. |
| `opts.transport` | Replace HTTP requests. |
| `opts.gzip`, `opts.chunk_size` | Select compressed document streaming and its read size. |
| `opts.max_response_bytes`, `opts.max_output_bytes` | HTTP response and decompressed byte limits. |
| `yamlcamel.limits` | Shared parser, emitter, tag and transfer ceilings; adjust them only for input you control. |

## Build & Deploy

Use Lua 5.4 or newer. Run `luarocks make --local yamlcamel-lua-scm-1.rockspec` from the checkout, or put `src/?.lua` and `src/?/init.lua` on `LUA_PATH` and require `yamlcamel` directly. Install `lua-zlib` for the default gzip helper and `http` for the default HTTP transport; an embed supplying its own implementations does not need them. Install Busted and run `busted` for the test suite. The core library has no compilation step.

Build the versioned package with `luarocks make --deps-mode=none --pack-binary-rock yamlcamel-lua-0.1.0-1.rockspec`. Use the SCM recipe when working from the development branch.

## License

PolyForm Noncommercial 1.0.0 OR PolyForm Small Business 1.0.0, at your choice. Source-available, but not open-source. See [License](LICENSE.MD) for the full terms.

The Noncommercial option permits noncommercial use. The Small Business option also permits use for a company's benefit when it has fewer than 100 employees and independent contractors combined and less than USD 1,000,000 in prior-tax-year revenue, measured in 2019 dollars and adjusted for inflation as the licence specifies. Its company definition includes related organisations under common control. Both options permit modifications and redistribution for their permitted purposes, subject to their conditions.

## Forking and Contributions

The [License](LICENSE.MD) permits modifications, forks and redistribution for the permitted purposes of either option, subject to its conditions. Our [Contribution Policy](CONTRIBUTING.md) also grants additional permissions for contribution forks, review and controlled testing. The limits and deadlines on that additional permission do not narrow independent rights granted by the software licence, applicable law or the hosting platform's terms.

Contributions are welcome. You retain ownership, but Spark may use and commercially relicense submitted contributions, including under proprietary terms, even if a submission is declined or withdrawn. Read and accept the contribution agreement before submitting a change.
