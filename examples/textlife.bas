10 REM Conway's Game of Life - Text Mode
20 REM 60x20 grid using LOCATE and COLOR
30 REM
40 PRINT "Initializing Text Life..."
50 LET W = 60
60 LET H = 20
70 DIM GRID(60, 20)
80 DIM NEXT(60, 20)
90 REM
100 REM Initialize with random pattern (30% alive)
110 PRINT "Seeding random pattern..."
120 FOR Y = 1 TO H
130   FOR X = 1 TO W
140     IF RND(1) < 0.3 THEN GRID(X, Y) = 1 ELSE GRID(X, Y) = 0
150   NEXT X
160 NEXT Y
170 REM
180 REM Start simulation
190 PRINT "Starting simulation..."
200 PRINT "Press CTRL-C to stop"
210 FOR I = 1 TO 1000
220 NEXT I
230 CLS
240 REM
250 REM Main simulation loop
260 FOR GEN = 1 TO 500
270   REM Draw current generation
280   COLOR 10
290   LOCATE 1, 1
300   PRINT "Generation: "; GEN; "  "
310   FOR Y = 1 TO H
320     LOCATE Y + 1, 1
330     FOR X = 1 TO W
340       IF GRID(X, Y) = 1 THEN PRINT CHR$(219); ELSE PRINT " ";
350     NEXT X
360   NEXT Y
370   REM
380   REM Calculate next generation
390   FOR Y = 1 TO H
400     FOR X = 1 TO W
410       LET N = 0
420       REM Count neighbors
430       FOR NY = Y - 1 TO Y + 1
440         FOR NX = X - 1 TO X + 1
450           IF NX >= 1 AND NX <= W AND NY >= 1 AND NY <= H THEN GOSUB 650
460         NEXT NX
470       NEXT NY
480       REM
490       REM Apply Life rules
500       IF N = 3 THEN NEXT(X, Y) = 1
510       IF N = 2 THEN NEXT(X, Y) = GRID(X, Y)
520       IF N < 2 OR N > 3 THEN NEXT(X, Y) = 0
530     NEXT X
540   NEXT Y
550   REM
560   REM Copy next to current
570   FOR Y = 1 TO H
580     FOR X = 1 TO W
590       GRID(X, Y) = NEXT(X, Y)
600     NEXT X
610   NEXT Y
620   REM Small delay
630   SLEEP 0.05
640 NEXT GEN
650 REM Subroutine: count neighbor at NX, NY
660 IF NX = X AND NY = Y THEN RETURN
670 IF GRID(NX, NY) = 1 THEN N = N + 1
680 RETURN
690 REM
700 REM End simulation
710 LOCATE 23, 1
720 COLOR 7
730 PRINT "Simulation complete!"
740 END
