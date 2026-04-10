10 REM EXAMPLE_HOME.BAS
20 REM Sample three-panel homepage: intro text, HGR graphics, closing note.
30 REM Copy to HOME.BAS in your directory and visit /<username> to see it.
40 REM
50 REM ================================================================
60 REM  PANEL 1: Introduction with colour effects
70 REM ================================================================
80 COLOR 14, 0
90 PRINT "  " + STRING$(56, 61)
100 PRINT "    MY ERLBASIC HOMEPAGE"
110 PRINT "  " + STRING$(56, 61)
120 PRINT
130 COLOR 7, 0
140 PRINT "  Welcome!  This page is built entirely in BASIC."
150 PRINT "  Each coloured panel is created by one HOME PUBLISH call."
160 PRINT
170 COLOR 11, 0
180 PRINT "  About me:"
190 PRINT
200 COLOR 7, 0
210 PRINT "    Username  : alice"
220 PRINT "    Project   : [1, 2]"
230 PRINT "    System    : ErlBASIC"
240 PRINT
250 COLOR 10, 0
260 PRINT "  Programs I have written:"
270 PRINT
280 COLOR 7, 0
290 PRINT "    GRAPHICS.BAS  - HGR shape demo"
300 PRINT "    TICTACTOE.BAS - Tic-tac-toe"
310 PRINT "    LIFE.BAS      - Conway's Life"
320 HOME PUBLISH
330 REM
340 REM ================================================================
350 REM  PANEL 2: HGR graphics
360 REM  Vertical CGA colour bars with concentric circle rings overlaid.
370 REM  Each bar shows colour N (1-15); circles step through colours
380 REM  so the centre ring is white and the outer rings fade to dark.
390 REM ================================================================
400 HGR
410 REM Vertical colour bars (colours 1-15, each bar ~53 px wide)
420 FOR I = 1 TO 15
430   X1 = (I - 1) * 53
440   X2 = X1 + 52
450   RECT (X1, 0)-(X2, 599), I
460 NEXT I
470 REM Concentric circle rings (outermost = colour 1, innermost = colour 15)
480 FOR I = 15 TO 1 STEP -1
490   CIRCLE (400, 300), I * 18, 16 - I
500 NEXT I
510 REM White border frame
520 LINE (0, 0)-(799, 0), 15
530 LINE (0, 599)-(799, 599), 15
540 LINE (0, 0)-(0, 599), 15
550 LINE (799, 0)-(799, 599), 15
560 HOME PUBLISH
570 REM
580 REM ================================================================
590 REM  PANEL 3: Closing note
600 REM ================================================================
610 COLOR 12, 0
620 PRINT "  " + STRING$(56, 61)
630 PRINT "    ABOUT THIS PAGE"
640 PRINT "  " + STRING$(56, 61)
650 PRINT
660 COLOR 7, 0
670 PRINT "  This homepage was written entirely in BASIC."
680 PRINT "  No HTML, CSS, or web knowledge was needed."
690 PRINT
700 COLOR 14, 0
710 PRINT "  How HOME PUBLISH works:"
720 PRINT
730 COLOR 7, 0
740 PRINT "    1. Write BASIC using PRINT, COLOR and LOCATE."
750 PRINT "    2. Call HOME PUBLISH to snapshot the text screen."
760 PRINT "    3. For graphics: use HGR, then RECT, CIRCLE, LINE."
770 PRINT "    4. Call HOME PUBLISH again to capture the canvas as SVG."
780 PRINT "    5. Repeat for more panels, then END."
790 PRINT
800 COLOR 13, 0
810 PRINT "  Good luck and happy coding!"
820 HOME PUBLISH
830 END
