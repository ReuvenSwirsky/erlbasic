10 REM Conway's Game of Life - Text Mode (Fast Renderer)
20 REM Uses reduced cursor movement and lightweight rendering
30 REM
40 PRINT "Initializing Text Life (fast)..."
50 LET W = 60
60 LET H = 20
70 DIM GRID(61, 21)
80 DIM NEXTGRID(61, 21)
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
230 CLS
240 COLOR 10
250 REM Main simulation loop
260 FOR GEN = 1 TO 500
270   REM Draw current generation (skip header for maximum render speed)
280   LOCATE 1, 1
290   FOR Y = 1 TO H
300     FOR X = 1 TO W
310       IF GRID(X, Y) = 1 THEN PRINT "#"; ELSE PRINT " ";
320     NEXT X
330     PRINT ""
340   NEXT Y
380   REM Calculate next generation
390   FOR Y = 1 TO H
400     FOR X = 1 TO W
410       LET N = GRID(X - 1, Y - 1) + GRID(X, Y - 1) + GRID(X + 1, Y - 1)
420       LET N = N + GRID(X - 1, Y) + GRID(X + 1, Y)
430       LET N = N + GRID(X - 1, Y + 1) + GRID(X, Y + 1) + GRID(X + 1, Y + 1)
480       REM Apply Life rules
490       IF N = 3 THEN NEXTGRID(X, Y) = 1
500       IF N = 2 THEN NEXTGRID(X, Y) = GRID(X, Y)
510       IF N < 2 OR N > 3 THEN NEXTGRID(X, Y) = 0
520     NEXT X
530   NEXT Y
540   REM Copy next to current
550   FOR Y = 1 TO H
560     FOR X = 1 TO W
570       GRID(X, Y) = NEXTGRID(X, Y)
580     NEXT X
590   NEXT Y
600 NEXT GEN
610 REM End simulation
620 LOCATE 23, 1
630 COLOR 7
640 PRINT "Simulation complete!"
650 END
