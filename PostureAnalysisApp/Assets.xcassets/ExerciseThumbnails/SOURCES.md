# Exercise thumbnail sources

This is the developer-facing source of truth for the bundled exercise photography. All six sources were explicitly approved in [issue #62](https://github.com/nintendom1/fix-my-posture/issues/62). Reconfirmed and retrieved on 2026-10-23. Do not substitute another photograph without approval.

## Asset and source mapping

Asset names below include the Xcode `ExerciseThumbnails` namespace. Each corresponding `<exercise_id>.imageset` contains only the final `<exercise_id>.jpg` and its `Contents.json`. `ExercisePhotography` supplies these same asset names and exact original-source links to the app.

| Exercise | Asset name | Photographer | Source / exact original page | Source ID | License / status |
| --- | --- | --- | --- | --- | --- |
| Air Squat | `ExerciseThumbnails/air_squat` | Polina Tankilevitch | [Pexels](https://www.pexels.com/photo/women-working-out-in-the-room-6516212/) | 6516212 | Pexels License |
| Dumbbell Row | `ExerciseThumbnails/dumbbell_row` | Airam Dato-on | [Pexels](https://www.pexels.com/photo/woman-lifting-weights-in-a-gym-13106582/) | 13106582 | Pexels License |
| Hammer Curl | `ExerciseThumbnails/hammer_curl` | Staff Sgt. Lucas Vega | [DVIDS / U.S. Marine Corps](https://www.dvidshub.net/image/6272440/okinawa-marine-maintains-physical-readiness-covid-19-environment) | 6272440; VIRIN 200710-M-CX982-0165 | U.S. government work; public domain in the United States |
| Push-Up | `ExerciseThumbnails/push_up` | Polina Tankilevitch | [Pexels](https://www.pexels.com/photo/woman-doing-push-up-6516167/) | 6516167 | Pexels License |
| Shoulder Press | `ExerciseThumbnails/shoulder_press` | Senior Airman Greydon Furstenau | [U.S. Air Force / Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Discipline_in_motion,_Incirlik_Airman_inspires_others_through_fitness_(9444781).jpg) | 9444781; VIRIN 251104-F-XM554-1092 | U.S. government work; public domain in the United States |
| Triceps Extension | `ExerciseThumbnails/triceps_extension` | Miguel González | [Pexels](https://www.pexels.com/photo/a-woman-lifting-a-dumbbell-14623619/) | 14623619 | Pexels License |

## Processing

Only deterministic square cropping and Lanczos resizing were applied. Each app asset is a 512 × 512 JPEG, quality 85, with optimized encoding. No generative processing, background removal, retouching, relighting, color adjustment, mirroring, padding, or aspect-ratio distortion was performed. Original full-resolution files are not retained in this repository.

The same canonical asset is reused in every thumbnail. At runtime, wider Quick Start tiles aspect-fill and clip it with an exercise-specific vertical crop anchor: top for Shoulder Press and Dumbbell Row, 25% for Air Squat, and center for the other exercises. This keeps heads and defining joints/equipment visible in the wide format; square thumbnails show the entire prepared crop.

Crop coordinates are pixel bounds `(left, top, right, bottom)`, with an exclusive right/bottom edge, in the retrieved image after reading its orientation. Every input had normal EXIF orientation.

| Exercise | Retrieved dimensions | Square crop bounds | Composition |
| --- | --- | --- | --- |
| Air Squat | 3000 × 2000 | `(1650, 500, 2950, 1800)` | Isolates the right-hand squatting subject, including head, bent knees, and both shoes. |
| Dumbbell Row | 2048 × 3072 | `(650, 850, 2048, 2248)` | Removes ceiling/floor space while keeping the bent torso, supporting arm, dumbbell, and feet. |
| Hammer Curl | 1999 × 1414 | `(0, 0, 1414, 1414)` | Focuses on the foreground subject, bent elbow, neutral grip, and dumbbell; no prominent military identifiers. |
| Push-Up | 2000 × 3000 | `(150, 1150, 2000, 3000)` | Removes tall empty space above the subject while retaining the complete planted-hand, extended-leg silhouette. The tucked knee is present in the approved source. |
| Shoulder Press | 7419 × 4946 | `(4700, 800, 7400, 3500)` | Isolates the reflected subject, keeping both raised elbows and dumbbells; excludes most foreground occlusion and overhead signage. No prominent military identifiers. |
| Triceps Extension | 4672 × 7008 | `(900, 850, 4300, 4250)` | Focuses on the overhead elbows, hands, and dumbbell behind the head; excludes lower-body and floor space. |

## Retrieval and licensing

The four Pexels files were retrieved using the original **Free download** link exposed by each exact approved source page, rather than an edited/AI derivative. The link format is `https://images.pexels.com/photos/<ID>/pexels-photo-<ID>.jpeg?cs=srgb&dl=<download-filename>&fm=jpg`. Download filenames were `pexels-polina-tankilevitch-6516212.jpg`, `pexels-polina-tankilevitch-6516167.jpg`, `pexels-airamdphoto-13106582.jpg`, and `pexels-mikegles-14623619.jpg`. Their use is under the [Pexels License](https://www.pexels.com/license/).

The Hammer Curl file is the 2000-pixel image linked from the approved DVIDS page: `https://d1ldvf68ux039x.cloudfront.net/thumbs/photos/2007/6272440/2000w_q95.jpg` (actual dimensions 1999 × 1414). The page identifies the photographer, a capture date of July 13, 2020, and public-domain status. The page’s gallery ordinal is inconsistent; photo ID **6272440** and VIRIN **200710-M-CX982-0165** identify the approved photograph.

The Shoulder Press file is the **Original file** linked from the approved Commons page: `https://upload.wikimedia.org/wikipedia/commons/d/df/Discipline_in_motion%2C_Incirlik_Airman_inspires_others_through_fitness_%289444781%29.jpg`. Commons identifies it as an official U.S. Air Force work, public domain in the United States. Its caption and EXIF describe capture on November 4, 2025 (the Commons summary’s date field says November 3).

Government photography is subject to the [DVIDS use limitations and non-endorsement requirements](https://www.dvidshub.net/about/copyright). Crops avoid unnecessarily prominent military identifiers; no endorsement is implied. The in-app acknowledgements and third-party notices include the source’s non-endorsement disclaimer.

## Final asset checksums (SHA-256)

| Asset file | SHA-256 |
| --- | --- |
| `air_squat.imageset/air_squat.jpg` | `f2b78a57763998bea359b0b4fffa0498f16449ef43c177604c9364065b8eca48` |
| `dumbbell_row.imageset/dumbbell_row.jpg` | `35d9a58e89b9d15f25f3592ea7afcaaba0cd1ff3794dbfd42d9e6fbaadc716ff` |
| `hammer_curl.imageset/hammer_curl.jpg` | `74f13bc7bca79e46cf4bd2dcd1310a4cf4edf86f2f5fb4e57e0078c370cae754` |
| `push_up.imageset/push_up.jpg` | `2e7eefee97d582882ab67d3d2ddcdaf8cf6a28dd235f76eb124c1345160b8b12` |
| `shoulder_press.imageset/shoulder_press.jpg` | `23a7294635e58c4b5dbff282b5e5d8c94886c49b4068172b47a7ed96ce236582` |
| `triceps_extension.imageset/triceps_extension.jpg` | `dcfc01c87bde5f19cb9a228e6eb920461a628e0e0c3711ea6b9316c83b820d90` |

## Maintenance

When adding, replacing, removing, renaming, or materially changing a thumbnail, keep this manifest, its asset-catalog entry, `ExercisePhotography`, `THIRD_PARTY_NOTICES.md`, and the in-app Exercise Photography acknowledgements synchronized. Use only vetted real photography, crop/resize only, and preserve instructional visuals. Stop and report source/provenance/crop problems; never silently substitute an image.
