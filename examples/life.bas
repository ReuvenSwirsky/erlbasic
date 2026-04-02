10 REM Conway's Game of Life
20 REM 64x48 grid, 10x10 pixels per cell
30 REM
40 PRINT "Initializing Conway's Life..."
50 LET W = 64
60 LET H = 48
70 LET CELLSIZE = 10
80 DIM GRID(64, 48)
90 DIM NEXT(64, 48)
100 REM
110 REM Initialize with random pattern (30% alive)
120 PRINT "Seeding random pattern..."
130 FOR Y = 1 TO H
140   FOR X = 1 TO W
150     IF RND(1) < 0.3 THEN GRID(X, Y) = 1
160     IF RND(1) >= 0.3 THEN GRID(X, Y) = 0
170   NEXT X
180 NEXT Y
190 REM
200 REM Switch to graphics mode
210 PRINT "Starting simulation..."
220 FOR I = 1 TO 1000
230 NEXT I
240 HGR
250 REM
260 REM Main simulation loop
270 FOR GEN = 1 TO 200
280   REM Draw current generation
290   FOR Y = 1 TO H
300     FOR X = 1 TO W
310       LET PX = (X - 1) * CELLSIZE
320       LET PY = (Y - 1) * CELLSIZE
330       IF GRID(X, Y) = 1 THEN LET C = 15
340       IF GRID(X, Y) = 0 THEN LET C = 0
350       REM Draw filled rectangle
360       RECT (PX, PY) - (PX + CELLSIZE - 1, PY + CELLSIZE - 1), C
370     NEXT X
380   NEXT Y
420   REM
430   REM Calculate next generation
440   FOR Y = 1 TO H
450     FOR X = 1 TO W
460       LET N = 0
470       REM Count neighbors
480       FOR NY = Y - 1 TO Y + 1
490         FOR NX = X - 1 TO X + 1
500           IF NX >= 1 AND NX <= W AND NY >= 1 AND NY <= H THEN GOSUB 700
510         NEXT NX
520       NEXT NY
530       REM
540       REM Apply Life rules
550       IF GRID(X, Y) = 1 AND (N = 2 OR N = 3) THEN NEXT(X, Y) = 1
560       IF GRID(X, Y) = 1 AND (N < 2 OR N > 3) THEN NEXT(X, Y) = 0
570       IF GRID(X, Y) = 0 AND N = 3 THEN NEXT(X, Y) = 1
580       IF GRID(X, Y) = 0 AND N <> 3 THEN NEXT(X, Y) = 0
590     NEXT X
600   NEXT Y
610   REM
620   REM Copy next to current
630   FOR Y = 1 TO H
640     FOR X = 1 TO W
650       GRID(X, Y) = NEXT(X, Y)
660     NEXT X
670   NEXT Y
680 NEXT GEN
690 GOTO 750
700 REM Subroutine: count neighbor at NX, NY
710 IF NX = X AND NY = Y THEN RETURN
720 IF GRID(NX, NY) = 1 THEN N = N + 1
730 RETURN
740 REM
750 REM End simulation
760 TEXT
770 PRINT "Simulation complete!"
780 END
