# ezstd

[![Build Status](https://app.travis-ci.com/silviucpp/ezstd.svg?branch=master)](https://travis-ci.com/github/silviucpp/ezstd)
[![GitHub](https://img.shields.io/github/license/silviucpp/ezstd)](https://github.com/silviucpp/ezstd/blob/master/LICENSE)
[![Hex.pm](https://img.shields.io/hexpm/v/ezstd)](https://hex.pm/packages/ezstd)

## [Zstd][1] binding for Erlang

This binding is based on zstd v1.5.7. The build is pinned to an immutable commit SHA (not just the tag) to protect against supply-chain attacks where a mutable tag is re-pointed at a malicious commit. In case you want to modify the `zstd` version, update **both** `ZSTD_TAG` and `ZSTD_SHA` in `build_deps.sh`. You can find the commit a tag resolves to with:

```sh
git ls-remote https://github.com/facebook/zstd.git 'v1.5.7^{}'
```

`build_deps.sh` checks out `ZSTD_SHA` directly and will refuse to build if the tag no longer resolves to the pinned commit.

## API

### Compress and decompress

```erl
Plaintext = <<"contentcontentcontentcontent">>,
Compressed = ezstd:compress(Plaintext, 1),
Plaintext = ezstd:decompress(Compressed).
```

### Compress and decompress using dictionary

```erl
Dict = <<"content-dict">>,
CDict = ezstd:create_cdict(Dict, 1),
DDict = ezstd:create_ddict(Dict),
Plaintext = <<"contentcontentcontentcontent">>,
ContentCompressed = ezstd:compress_using_cdict(Plaintext, CDict),
Plaintext = ezstd:decompress_using_ddict(ContentCompressed, DDict).
```

## Running tests

```sh
rebar3 ct
```

[1]: http://facebook.github.io/zstd/
