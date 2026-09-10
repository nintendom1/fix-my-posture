# Photo Validation Rules

`PhotoValidator` evaluates standing photos before analysis to issue non-blocking warnings:

1. **Total Detected Landmarks**: Flags when fewer than 6 landmarks are found.
2. **Key Landmarks**: Checks for critical joints (`neck`, `leftShoulder`, `rightShoulder`, `leftHip`, `rightHip`, `leftAnkle`, `rightAnkle`).
3. **Detection Confidence**: Flags landmarks with confidence below `0.30`.
4. **Cropping Detection**: Checks if head or feet landmarks lie within `2%` of image top/bottom borders.
5. **Frame Span**: Flags photos where body height occupies less than `45%` of frame height.
