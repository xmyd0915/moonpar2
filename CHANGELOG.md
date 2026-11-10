# Changelog

## 0.4.0

- Split output into an index and self-contained recovery volumes with `--volume-blocks`; each recovery volume carries repeated metadata.
- Discover sibling volumes from an index or any recovery volume, with `--no-discovery` for explicit input selection.
- Add `split_volume` to preserve packets and recovery exponents while regrouping existing complete volumes.
- Stage all split outputs before exclusive publication; preserve existing files and roll back owned outputs after a write failure.
- Verify missing-index recovery, damaged-volume recovery and bidirectional multi-volume interoperability with par2cmdline.
- Accept the documented 16 MiB slice size in numeric CLI options and reject overflowing integers.

## 0.3.0

- Unicode paths, UTF-16LE Unicode Filename packets and UTF-8 FileDesc interoperability.
- Streaming create, verify and repair callbacks with UInt64 sizes and offsets; Node CLI uses bounded-memory file access by default.
- Incremental MD5, in-place residual decoding and verified staging before output publication.
- Chinese/Japanese/emoji recovery tested in both directions with par2cmdline and MultiPar.
- MultiPar verifies non-recovery metadata and repairs recovery members; the par2cmdline 1.4.0 defect is documented separately.
- Large-file acceptance under a 256 MiB Node heap, interrupted-write cleanup and exact output hashes.

## 0.2.0

- Recursive directory input and nested recovery output, explicit data roots, empty files and check-only members.
- Bytewise packet resynchronization with damaged-packet diagnostics; repeated critical metadata in newly created volumes.
- Creator inspection and failure context, safe relative paths, ancestor symlink/junction rejection and output collision protection.
- 256 MiB source budget, 4096 files and 32768 source slices; repair avoids a second file-sized output copy.
- Independent packet byte comparison, directory/damaged-volume repairs in both tools, hostile archive paths, full capacity and file-count boundaries.
- Published core conformance matrix and executable walkthrough; known non-recovery-list reference-tool limitation reported separately.

## 0.1.0

- Initial MoonBit PAR2 library and Node CLI with create, verify and non-overwriting repair.
- 64 MiB flat file sets and bidirectional par2cmdline tests on Windows and Ubuntu.
