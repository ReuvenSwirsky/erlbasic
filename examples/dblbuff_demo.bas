10 REM DBLBUFF_DEMO.BAS - Double-buffer, FLUSH, PGET, GETCHAR demo
20 REM
30 REM Demonstrates:
40 REM   DBLBUFF ON/OFF  - batch graphics frames into one WebSocket message
50 REM   FLUSH           - send buffered frames to the browser at a chosen point
60 REM   PGET (x,y), v  - read palette index of a canvas pixel
70 REM   GETCHAR r,c, s$ - read a character from a terminal cell
80 REM
90 REM ================================================================
100 REM PART 1: DBLBUFF + FLUSH  (fill screen with colour bars)
110 REM ================================================================
120 PRINT "Part 1: Drawing 16 colour bars with DBLBUFF + FLUSH ..."
130 PRINT "  All 16 RECT commands are batched and sent in one message."
140 DBLBUFF ON
150 HGR
160 LET BARW = 50
170 FOR C = 0 TO 15
180   LET X1 = C * BARW
190   LET X2 = X1 + BARW - 1
200   RECT (X1, 0) - (X2, 599), C
210 NEXT C
220 FLUSH
230 REM  Canvas now shows 16 colour bars.  Pause so the user can see them.
240 SLEEP 2
250 REM
260 REM ================================================================
270 REM PART 2: PGET  (read pixels while canvas is still visible)
280 REM ================================================================
290 REM Bar 14 spans x=700-749, its centre is at x=725  (yellow, palette 14)
300 REM Bar  2 spans x=100-149, its centre is at x=125  (green,  palette  2)
310 PGET (725, 300), P14
320 PGET (125, 300), P2
330 TEXT
340 DBLBUFF OFF
350 PRINT "Part 2: PGET - reading pixels from the canvas ..."
360 PRINT "  Bar 14 centre (yellow, expect 14): "; P14
370 PRINT "  Bar  2 centre (green,  expect  2): "; P2
380 PRINT ""
390 SLEEP 3
400 REM
410 REM ================================================================
420 REM PART 3: GETCHAR  (write text and read it back from the terminal)
430 REM ================================================================
440 PRINT "Part 3: GETCHAR - printing 'ERLANG' then reading each letter ..."
450 LOCATE 20, 1
460 PRINT "ERLANG";
470 GETCHAR 20, 1, C1$
480 GETCHAR 20, 2, C2$
490 GETCHAR 20, 3, C3$
500 GETCHAR 20, 4, C4$
510 GETCHAR 20, 5, C5$
520 GETCHAR 20, 6, C6$
530 LOCATE 22, 1
540 COLOR 11
550 PRINT "  Read back: "; C1$; C2$; C3$; C4$; C5$; C6$; " (expect ERLANG)"
560 COLOR 7
570 PRINT ""
580 SLEEP 3
590 REM
600 REM ================================================================
610 REM PART 4: Smooth animation via DBLBUFF + FLUSH
620 REM ================================================================
630 PRINT "Part 4: Animated diagonal gradient (20 frames x 200 ms = 4 s) ..."
640 PRINT "  Watch the canvas: each frame is drawn, flushed, THEN paused."
650 SLEEP 2
660 DBLBUFF ON
670 HGR
680 FOR FRAME = 0 TO 19
690   REM  Draw the full 800x600 grid of coloured rectangles for this frame
700   FOR Y = 0 TO 599 STEP 40
710     FOR X = 0 TO 799 STEP 50
720       LET C = (INT(X / 50) + INT(Y / 40) + FRAME) MOD 16
730       RECT (X, Y) - (X + 49, Y + 39), C
740     NEXT X
750   NEXT Y
760   REM  FLUSH sends every RECT in one shot, THEN SLEEP waits for next frame
770   FLUSH
780   SLEEP 0.2
790 NEXT FRAME
800 REM
810 TEXT
820 DBLBUFF OFF
830 PRINT ""
840 PRINT "Part 4 complete.  Demo finished!"
850 END
