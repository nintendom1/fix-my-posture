# Source Artwork: Chibi Character PSD

`chibis_600x400.psd` is the unmodified file from the Female Character Chibi Sprite pack. The
notification portraits are rendered from its layers by [`../render_character.py`](../README.md).
Do not edit it; the renderer refuses to run if its SHA-256 changes.

| | |
|---|---|
| File | `chibis_600x400.psd`, 4,445,430 bytes, 400×600 px, RGB, 86 layers and groups |
| SHA-256 | `d0a47af46065ba5bbfe34b987f31a80f44742458f291c832ae4e9d6f139d34cd` |
| Chibi pack | [Female Character Chibi Sprite](https://dicortesia.itch.io/female-character-chibi) by dicortesia |
| Original characters | [Female Character Sprite for Visual Novel](https://sutemo.itch.io/female-character) by Sutemo, which the chibi pack is based on |
| Terms checked | 2026-10-22 |

The pack's other file, `chibis_800x533.psd`, is deliberately not included. Its author calls it lower quality. We
compared it with this file on 2026-10-22: it has the same 86 layers, each about 1.33× larger, and every layer matches a
soft upscale of this file's layer to within about 0.75/255 on average, with wider edges and less mid-frequency detail.
It is an enlargement, not a higher-detail source, so it would only add 6.8 MB to history.

## Terms

Neither author ships a license file. The terms are the text on their itch.io pages, quoted here as
they read on 2026-10-22 because those pages can change.

dicortesia, Female Character Chibi Sprite:

> Feel free to use them however you wish, including commercial projects!
> However, you cannot resell them, or use them for NFTs.
> Credit is appreciated!

> Feel free to alter them however you want!

The page also tags the pack "No generative AI was used".

Sutemo, Female Character Sprite for Visual Novel:

> This sprite can be used in personal or commercial projects. however you can't resell the sprite on its own.

## What this means here

- Using the artwork in the app, including rendered portraits, is allowed. That covers commercial use and altering
  the artwork.
- Do not sell the PSD or the portraits as assets, and do not use either for NFTs.
- Credit both authors. See [`THIRD_PARTY_NOTICES.md`](../../../THIRD_PARTY_NOTICES.md). The in-app Acknowledgements entry
  is added when portraits ship in the app bundle.
- This repository is public, so committing the PSD republishes the whole pack: five hair colors, eleven
  expressions, and nine outfits. The terms above allow free use but not resale. The PSD is not covered by any
  license this repository has. If either author asks for removal, delete the file and stop rendering from it.
- The authors' pages are the only record of the terms. If they change, update this file and the notices.
