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
150     IF RND(1) < 0.3 THEN GRID(X, Y) = 1 ELSE GRID(X, Y) = 0
160   NEXT X
170 NEXT Y
180 REM
190 REM Switch to graphics mode
200 PRINT "Starting simulation..."
210 HGR
220 REM
230 REM Main simulation loop
240 FOR GEN = 1 TO 200
250   REM Draw current generation
260   FOR Y = 1 TO H
270     FOR X = 1 TO W
280       LET PX = (X - 1) * CELLSIZE
290       LET PY = (Y - 1) * CELLSIZE
300       IF GRID(X, Y) = 1 THEN LET C = 15 ELSE LET C = 0
310       RECT (PX, PY) - (PX + CELLSIZE - 1, PY + CELLSIZE - 1), C
320     NEXT X
330   NEXT Y
340   REM
350   REM Calculate next generation
360   FOR Y = 1 TO H
370     FOR X = 1 TO W
380       LET N = 0
390       REM Count neighbors
400       FOR NY = Y - 1 TO Y + 1
410         FOR NX = X - 1 TO X + 1
420           IF NX >= 1 AND NX <= W AND NY >= 1 AND NY <= H THEN GOSUB 600
430         NEXT NX
440       NEXT NY
450       REM
460       REM Apply Life rules: born with 3, survive with 2-3
470       IF N = 3 THEN NEXT(X, Y) = 1
480       IF N = 2 THEN NEXT(X, Y) = GRID(X, Y)
490       IF N < 2 OR N > 3 THEN NEXT(X, Y) = 0
500     NEXT X
510   NEXT Y
520   REM
530   REM Copy next to current
540   FOR Y = 1 TO H
550     FOR X = 1 TO W
560       GRID(X, Y) = NEXT(X, Y)
570     NEXT X
580   NEXT Y
590 NEXT GEN
600 REM Subroutine: count neighbor at NX, NY
610 IF NX = X AND NY = Y THEN RETURN
620 IF GRID(NX, NY) = 1 THEN N = N + 1
630 RETURN
640 REM
650 REM End simulation
660 TEXT
670 PRINT "Simulation complete!"
680 END
