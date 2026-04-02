10 REM Simple animation test
20 PRINT "Starting animation test..."
30 HGR
40 REM Draw 10 frames
50 FOR I = 1 TO 10
60   RECT (100, 100) - (200, 200), I
70   SLEEP 0.5
80 NEXT I
90 TEXT
100 PRINT "Animation complete"
110 END
