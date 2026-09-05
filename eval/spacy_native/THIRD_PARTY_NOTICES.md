# Third-party notices for the native feasibility prototype

The tokenizer, feature extraction, CNN, and transition decoder are Rust ports of
algorithms in the pinned spaCy 3.8.13 and Thinc 8.3.13 implementations. Source
references are listed in README.md. Both projects are MIT licensed.

## spaCy

The MIT License (MIT)

Copyright (C) 2016-2024 ExplosionAI GmbH, 2016 spaCy GmbH, 2015 Matthew Honnibal

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

## Thinc

The MIT License (MIT)

Copyright (C) 2016 ExplosionAI GmbH, 2016 spaCy GmbH, 2015 Matthew Honnibal

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

## MurmurHash

MurmurHash algorithms by Austin Appleby are public domain. The native hash
implementation follows spaCy/Thinc's exact variants and seeds.

## Runtime libraries and model assets

The prototype dynamically links the system Apple Accelerate framework and the
locally installed PCRE2 library (BSD-3-Clause). It does not redistribute them.
Rust dependency versions are recorded in Cargo.lock: serde (MIT/Apache-2.0),
serde_json (MIT/Apache-2.0), memmap2 (MIT/Apache-2.0), and libc (MIT/Apache-2.0),
plus their transitive dependencies under their respective licenses.

Exported en_core_web_lg 3.8.0 assets remain local and are not committed or bundled.
See the repository's docs/model-asset-licensing.md and the installed model's
metadata for provenance and redistribution review before shipping assets.
