10 REM Test ON...GOSUB and ON...GOTO computed jumps
20 PRINT "Testing ON...GOSUB:"
30 FOR I = 1 TO 4
40 ON I GOSUB 200, 300, 400
50 NEXT I
60 PRINT
70 PRINT "Testing ON...GOTO:"
80 X = 2
90 ON X GOTO 500, 600, 700
100 REM Should not reach here
110 PRINT "ERROR: Should not reach here"
120 END
200 PRINT "Called subroutine 1"
210 RETURN
300 PRINT "Called subroutine 2"
310 RETURN
400 PRINT "Called subroutine 3"
410 RETURN
500 PRINT "Jumped to line 500"
510 END
600 PRINT "Jumped to line 600"
610 END
700 PRINT "Jumped to line 700"
710 END
