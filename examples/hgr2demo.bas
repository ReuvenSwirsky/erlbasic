10 REM HGR2 DEMO - 800x480 graphics + 4-line text area
20 REM Demonstrates mixed graphics and text in HGR2 mode.
30 REM Graphics region: rows 1-21 (800x480 canvas)
40 REM Text region:     rows 22-25 (use LOCATE 22-25)
50 REM
60 HGR2
70 REM
80 REM --- Background and border ---
90 RECT (0,0)-(799,479), 1
100 LINE (2,2)-(797,2), 15
110 LINETO (797,477), 15
120 LINETO (2,477), 15
130 LINETO (2,2), 15
140 REM
150 REM --- Title bar ---
160 RECT (2,2)-(797,22), 3
170 REM Draw "HGR2" as pixel blocks in the title
180 REM (simple 5x7 block letters, 1 block = 4x4 pixels, starting at x=320, y=5)
190 REM
200 REM --- 8 color circles across the top ---
210 FOR I = 0 TO 7
220   LET C = I + 1
230   LET X = 52 + I * 90
240   CIRCLE (X, 80), 35, C
250 NEXT I
260 REM
270 REM --- 8 bright-color filled rectangles ---
280 FOR I = 0 TO 7
290   LET C = I + 8
300   LET X = 52 + I * 90
310   RECT (X-32, 135)-(X+32, 175), C
320 NEXT I
330 REM
340 REM --- Rainbow diagonal lines ---
350 FOR I = 0 TO 15
360   LET X1 = 10 + I * 24
370   LINE (X1, 200)-(X1+200, 420), I
380 NEXT I
390 REM
400 REM --- Nested circles in the right half ---
410 FOR I = 1 TO 8
420   LET R = I * 18
430   CIRCLE (620, 320), R, 16 - I
440 NEXT I
450 REM
460 REM --- Filled triangle using horizontal lines ---
470 FOR Y = 250 TO 430
480   LET W = (Y - 250) / 2
490   LET X1 = 250 - W
500   LET X2 = 250 + W
510   LINE (X1, Y)-(X2, Y), 14
520 NEXT Y
530 REM
540 REM --- Text area: use LOCATE to stay in rows 22-25 ---
550 LOCATE 22, 1
560 PRINT "HGR2 MODE: 800x480 graphics + 4 text rows below"
570 LOCATE 23, 1
580 PRINT "Circles (1-8), Rectangles (9-15), Lines, Nested circles"
590 LOCATE 24, 1
600 PRINT "Triangle drawn with horizontal LINE sweeps (color 14)"
610 LOCATE 25, 1
620 COLOR 11
630 PRINT "Press any key to return to text mode...";
640 COLOR 7
650 SLEEP
660 TEXT
670 PRINT "HGR2 DEMO COMPLETE"
680 END
