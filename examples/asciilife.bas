10 REM Conway's Game of Life - Text Mode (Optimized for Speed)
20 REM Uses byte& and integer% types for faster computation
30 REM Single-pass neighbor counting using local variables
40 REM
50 PRINT "Initializing Text Life (optimized)..."
60 LET W% = 60
70 LET H% = 20
80 DIM GRID&(61, 21)
90 DIM NEXTGRID&(61, 21)
100 REM
110 REM Initialize with random pattern (30% alive)
120 PRINT "Seeding random pattern..."
130 FOR Y% = 1 TO H%
140   FOR X% = 1 TO W%
150     IF RND(1) < 0.3 THEN GRID&(X%, Y%) = 1 ELSE GRID&(X%, Y%) = 0
160   NEXT X%
170 NEXT Y%
180 REM
190 REM Start simulation
200 PRINT "Starting simulation..."
210 PRINT "Press CTRL-C to stop"
220 CLS
230 COLOR 10
240 REM Main simulation loop
250 FOR GEN% = 1 TO 500
260   REM Draw current generation
270   LOCATE 1, 1
280   FOR Y% = 1 TO H%
290     FOR X% = 1 TO W%
300       IF GRID&(X%, Y%) = 1 THEN PRINT "#"; ELSE PRINT " ";
310     NEXT X%
320     PRINT ""
330   NEXT Y%
340   REM
350   REM Calculate next generation (optimized)
360   FOR Y% = 1 TO H%
370     FOR X% = 1 TO W%
380       REM Count neighbors using local variables
390       LET N% = GRID&(X% - 1, Y% - 1) + GRID&(X%, Y% - 1) + GRID&(X% + 1, Y% - 1)
400       LET N% = N% + GRID&(X% - 1, Y%) + GRID&(X% + 1, Y%)
410       LET N% = N% + GRID&(X% - 1, Y% + 1) + GRID&(X%, Y% + 1) + GRID&(X% + 1, Y% + 1)
420       REM Apply Life rules
430       IF N% = 3 THEN NEXTGRID&(X%, Y%) = 1 ELSE IF N% = 2 THEN NEXTGRID&(X%, Y%) = GRID&(X%, Y%) ELSE NEXTGRID&(X%, Y%) = 0
440     NEXT X%
450   NEXT Y%
460   REM Copy next to current
470   FOR Y% = 1 TO H%
480     FOR X% = 1 TO W%
490       GRID&(X%, Y%) = NEXTGRID&(X%, Y%)
500     NEXT X%
510   NEXT Y%
520 NEXT GEN%
530 REM End simulation
540 LOCATE 23, 1
550 COLOR 7
560 PRINT "Simulation complete!"
570 END
