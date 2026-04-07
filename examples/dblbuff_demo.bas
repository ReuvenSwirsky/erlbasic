10 REM DBLBUFF_DEMO.BAS - Double-buffer, FLUSH, PGET, GETCHAR demo
20 REM
30 REM Demonstrates:
40 REM   DBLBUFF ON/OFF  - batch graphics frames into a single WebSocket message
50 REM   FLUSH           - send buffered frames to the browser at chosen sync point
60 REM   PGET (x,y), v  - read palette index of a canvas pixel
70 REM   GETCHAR r,c, s$ - read character from a terminal cell
80 REM
90 REM ---------------------------------------------------------------
100 REM PART 1: DBLBUFF + FLUSH  (fill screen with colour bars, fast)
110 REM ---------------------------------------------------------------
120 PRINT "Part 1: Drawing 16 colour bars with DBLBUFF + FLUSH ..."
130 DBLBUFF ON
140 HGR
150 REM Draw 16 vertical bars across the 800-pixel canvas
160 LET BARW = 50
170 FOR C = 0 TO 15
180   LET X1 = C * BARW
190   LET X2 = X1 + BARW - 1
200   RECT (X1, 0) - (X2, 599), C
210 NEXT C
220 FLUSH
230 REM
240 REM ---------------------------------------------------------------
250 REM PART 2: PGET - read two pixels back from the canvas
260 REM ---------------------------------------------------------------
270 REM Each bar is 50 px wide; centre of bar C is at x = C*50 + 25
280 REM Sample the centre of bar 14 (yellow) and bar 2 (green)
290 PGET (725, 300), P14
300 PGET (125, 300), P2
310 REM
320 REM ---------------------------------------------------------------
330 REM PART 3: GETCHAR - write text and read it back
340 REM ---------------------------------------------------------------
350 TEXT
360 DBLBUFF OFF
370 PRINT "Part 1 complete."
380 PRINT "PGET bar 14 (yellow, expect 14): "; P14
390 PRINT "PGET bar  2 (green,  expect  2): "; P2
400 REM
410 PRINT ""
420 PRINT "Part 2: GETCHAR test ..."
430 LOCATE 20, 1
440 PRINT "HELLO";
450 REM Read back each character we just printed
460 GETCHAR 20, 1, C1$
470 GETCHAR 20, 2, C2$
480 GETCHAR 20, 3, C3$
490 GETCHAR 20, 4, C4$
500 GETCHAR 20, 5, C5$
510 LOCATE 22, 1
520 COLOR 11
530 PRINT "Read back: "; C1$; C2$; C3$; C4$; C5$; " (expect HELLO)"
540 COLOR 7
550 REM
560 REM ---------------------------------------------------------------
570 REM PART 3: Animated gradient using DBLBUFF to stay smooth
580 REM ---------------------------------------------------------------
590 PRINT ""
600 PRINT "Part 3: Animated diagonal gradient (10 frames) ..."
610 SLEEP 1
620 DBLBUFF ON
630 HGR
640 FOR FRAME = 0 TO 9
650   REM Draw diagonal stripes that shift each frame
660   FOR Y = 0 TO 599 STEP 40
670     FOR X = 0 TO 799 STEP 50
680       LET C = (INT(X / 50) + INT(Y / 40) + FRAME) MOD 16
690       RECT (X, Y) - (X + 49, Y + 39), C
700     NEXT X
710   NEXT Y
720   FLUSH
730   SLEEP 0.12
740 NEXT FRAME
750 REM
760 TEXT
770 DBLBUFF OFF
780 PRINT "Demo complete."
790 END
