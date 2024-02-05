;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Percolation Model of Innovation in Complex Technology Spaces
; After the papers by Silverberg & Verspagen (2005; 2007)
; This version (C) Christopher Watts, 2014. See Info tab for terms and conditions of use.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

extensions [array]

globals [
  num-columns
  bpf
  baseline
  diamond-size
  
  patchqueue ; Array used for calculating paths. (Lists are inefficient as queues.)
  max-q-size ; Trouble with arrays is: we have to pre-state their max length.
  
  innov-sizes
  freq-distrib
  
  state-freq
  mean-height
  mean-pathlength
  
  num-reachable
  num-possible
  perc-reachable
  
  num-recent-changes
  num-changes
  deadlocked
  
  state-colors
]

patches-own [
  state
  bp-frontier
  pathlength
  tempdist
  diamond-neighbors
  visited
  reachable
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to setup
  clear-all
  reset-ticks
  
;  resize-world 0 max-pxcor (-1 * search-radius-m) max-pycor
  
  set state-colors array:from-list (list black white yellow pink lime (grey - 2))
  
  set num-columns 1 + max-pxcor - min-pxcor
  set max-q-size 1 + ((2 * search-radius-m) * (search-radius-m + 1))
  if (2 * num-columns) > max-q-size [set max-q-size (2 * num-columns)]
  set patchqueue array:from-list n-values max-q-size [nobody]
  set state-freq array:from-list n-values 4 [0]
  set bpf array:from-list n-values num-columns [nobody]
  set innov-sizes []
  set diamond-size (2 * search-radius-m * (search-radius-m + 1))
  
  ask patches [
    set tempdist -1
    set diamond-neighbors []
    ifelse pycor < 0 [
      set state 0
      set pcolor white
      set reachable false
    ]
    [
      ifelse chance-possible-q > random-float 100 [
        set state 1
        set pcolor array:item state-colors 1
      ]
      [
        set state 0
        set pcolor array:item state-colors 0
      ]
    ]
  ]
  
  set baseline patches with [pycor = 0]
  ask baseline [
    set state 3
    set pcolor array:item state-colors 3
  ]
  set num-possible count patches with [(state > 0) and (pycor > 0)]
  ask patches with [pycor > 0] [array:set state-freq state (1 + array:item state-freq state)]
  
  calc-pathlength-via-possibles
  calc-pathlength
  ask patches with [state = 3] [update-bpf]
  
  my-setup-plots
  my-update-plots
  
  set deadlocked false
  set num-changes 0
end

to calc-one-neighborhood
  ; Calculates a diamond shape of patches, m in radius, excluding the centre patch (caller).
  let cur-patch nobody
  let cur-step 0
  let cur-dx 0
  let cur-dy 0
  ;repeat m times
  ;start with square m above caller
  ;diagonal until pycor same
  ;diagonal until pxcor same
  ;diagonal until pycor same
  ;diagonal until pxcor same
  repeat search-radius-m [
    set cur-step cur-step + 1
    set cur-dx 0
    set cur-dy cur-step
    set cur-patch patch-at cur-dx cur-dy
    while [cur-dy != 0] [
      if cur-patch != nobody [
        set diamond-neighbors fput cur-patch diamond-neighbors
      ]
      set cur-dx cur-dx + 1
      set cur-dy cur-dy - 1
      set cur-patch patch-at cur-dx cur-dy
    ]
    while [cur-dx != 0] [
      if cur-patch != nobody [
        set diamond-neighbors fput cur-patch diamond-neighbors
      ]
      set cur-dx cur-dx - 1
      set cur-dy cur-dy - 1
      set cur-patch patch-at cur-dx cur-dy
    ]
    while [cur-dy != 0] [
      if cur-patch != nobody [
        set diamond-neighbors fput cur-patch diamond-neighbors
      ]
      set cur-dx cur-dx - 1
      set cur-dy cur-dy + 1
      set cur-patch patch-at cur-dx cur-dy
    ]
    while [cur-dx != 0] [
      if cur-patch != nobody [
        set diamond-neighbors fput cur-patch diamond-neighbors
      ]
      set cur-dx cur-dx + 1
      set cur-dy cur-dy + 1
      set cur-patch patch-at cur-dx cur-dy
    ]
  ]
end

to calc-one-neighborhood-old
  ; Calculates a diamond shape of patches, m in radius, excluding the centre patch (caller).
  let diamond []
  let cur-site nobody
  let q-start 0
  let q-size 0
  
  ; Add to queue
  array:set patchqueue (q-start + q-size) self
  set q-size (q-size + 1)
  set tempdist 0
  while [q-size > 0] [
    ; Take from start of queue.
    set q-size q-size - 1
    set cur-site array:item patchqueue q-start
    set q-start (q-start + 1)
    
    ask cur-site [
      if tempdist < search-radius-m [
        ask neighbors4 with [tempdist = -1] [
          set tempdist (1 + [tempdist] of myself)
          set diamond fput self diamond
          ; Add to end of queue
          array:set patchqueue (q-start + q-size) self
          set q-size (q-size + 1)
        ]
      ]
    ]
  ]
  foreach diamond [ ask ? [ set tempdist -1 ] ] ; Clean up
  set tempdist -1
  set diamond-neighbors diamond
end

to calc-pathlength-via-possibles
  ; Calculates minimum degree of separation from baseline
  ; via valid path, where valid paths consist only of neighbors4 in state >= 1.
  let cur-pathlength 0
  let q-start 0
  let q-size 0
  let cur-site nobody
  ask patches [set pathlength -1]
  ask baseline [
    array:set patchqueue ((q-start + q-size) mod max-q-size) self
    set q-size ((q-size + 1) mod max-q-size) ; Will do bad things, if q-size > max-q-size - i.e. we loop round on ourselves!
    set pathlength 0
  ]
  while [q-size > 0] [
    ; Take from start of queue.
    if q-size >= max-q-size [
      user-message (word "Queue is too big!")
      stop
    ]
    set q-size q-size - 1
    set cur-site array:item patchqueue q-start
    set q-start (q-start + 1) mod max-q-size
    
    ask cur-site [
      ;print (word self ": " pathlength) ;; For debugging
      set cur-pathlength pathlength
      ask neighbors4 with [state >= 1] [
        if pathlength = -1 [ ; Implies we haven't been here before.
          set pathlength cur-pathlength + 1
          ; Add to end of queue
          array:set patchqueue ((q-start + q-size) mod max-q-size) self
          set q-size ((q-size + 1) mod max-q-size)
        ]
      ]
    ]
  ]
  ask patches [set reachable ((pycor > 0) and (state > 0) and (pathlength != -1))]
  set num-reachable count patches with [reachable]
  set perc-reachable ifelse-value (num-possible = 0) [0] [num-reachable / num-possible]
  highlight-unreachables
end

to highlight-unreachables
  ask patches with [(pycor >= 0) and (state > 0) and (not reachable)] [set pcolor array:item state-colors 5]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to go
  if ticks >= max-ticks [stop]
  if deadlocked [stop]
  
  search-from-bpf
  
  calc-pathlength
  tick
  my-update-plots
  
  
end

to search-from-bpf
  let cur-diamond []
  let test-chance 0
  
  foreach (array:to-list bpf) [
    ask ? [
      ;print diamond-neighbors ;; For debugging
      if 0 = (length diamond-neighbors) [calc-one-neighborhood]
      set test-chance search-effort-e / diamond-size
      ;if (length diamond-neighbors) != diamond-size [print (word diamond-size ", " ? ": " (length diamond-neighbors) ", " diamond-neighbors)]
      ;print test-chance
      foreach diamond-neighbors [
        ask ? [
          ;  if state = 1 [ ; Possible. We don't bother counting the search for the impossible.
          ;    if reachable [ ; Only bother with reachable technologies.
          if (state = 1) [if reachable [search-site test-chance]]
        ]
      ]
    ]
  ]
end

to search-site [test-chance]
  if test-chance > random-float 1 [ ; Lucky?
    ; Discovered!
    set state 2
    set pcolor array:item state-colors 2
    array:set state-freq 2 (1 + array:item state-freq 2)
    array:set state-freq 1 (-1 + array:item state-freq 1)
    set num-changes num-changes + 1
    stop
  ]
end

to calc-pathlength
  ; Calculates minimum degree of separation from baseline
  ; via valid path, where valid paths consist only of neighbors4 in state 3.
  let cur-pathlength 0
  let q-start 0
  let q-size 0
  let cur-site nobody
  ask patches [set pathlength -1]
  ask baseline [
    array:set patchqueue ((q-start + q-size) mod max-q-size) self
    set q-size ((q-size + 1) mod max-q-size) ; NB. Will do bad things, if q-size > max-q-size - i.e. we'll loop round on ourselves!
    set pathlength 0
  ]
  while [q-size > 0] [
    ; Take from start of queue.
    if q-size >= max-q-size [ ; Error check
      user-message (word "Queue is too big!")
      stop
    ]
    set q-size q-size - 1
    set cur-site array:item patchqueue q-start
    set q-start (q-start + 1) mod max-q-size
    
    ask cur-site [
      ;print (word self ": " pathlength) ;; For debugging
      set cur-pathlength pathlength
      ask neighbors4 with [pathlength = -1] [ ; Implies we haven't been here before.
        if state >= 2 [ 
;      ask neighbors4 with [state >= 2] [
;        if pathlength = -1 [ ; Implies we haven't been here before.
          set pathlength cur-pathlength + 1
          if state = 2 [
            set state 3
            set pcolor array:item state-colors 3
            array:set state-freq 3 (1 + array:item state-freq 3)
            array:set state-freq 2 (-1 + array:item state-freq 2)
            set num-changes num-changes + 1
            update-bpf
          ]
          ; Add to end of queue
          array:set patchqueue ((q-start + q-size) mod max-q-size) self
          set q-size ((q-size + 1) mod max-q-size)
        ]
      ]
    ]
  ]
end

to update-bpf
  ; Recalculates the "best-practice frontier" in current patch's column
  ; BPF is in each column the highest point in state 3
  
  ifelse (array:item bpf pxcor) = nobody [
    array:set bpf pxcor self
    set pcolor array:item state-colors 4
  ]
  [
    if pycor > [pycor] of (array:item bpf pxcor) [
      ask (array:item bpf pxcor) [set pcolor array:item state-colors 3]
      set innov-sizes fput (pycor - [pycor] of (array:item bpf pxcor)) innov-sizes
      array:set bpf pxcor self
      set pcolor array:item state-colors 4
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to my-setup-plots
  set-current-plot "Progress"
  set-current-plot-pen "BPF Height"
  set-plot-pen-interval output-every
  set-current-plot-pen "Path Length"
  set-plot-pen-interval output-every
end

to my-update-plots
  if 0 = ticks mod output-every [
    set mean-height mean map [[pycor] of ?] array:to-list bpf
    set mean-pathlength mean [pathlength] of patches with [state = 3]
    
    set-current-plot "States"
    clear-plot
    let cur-state 0
    repeat 4 [
      plot array:item state-freq cur-state
      set cur-state cur-state + 1
    ]
    
    set-current-plot "Progress"
    set-current-plot-pen "BPF Height"
    plot mean-height
    set-current-plot-pen "Path Length"
    plot mean-pathlength
    
    if 0 < length innov-sizes [
      set freq-distrib []
      set-current-plot "Log-Log"
      clear-plot
      set innov-sizes sort innov-sizes
      let cur-val first innov-sizes
      let cur-freq 1
      foreach but-first innov-sizes [
        ifelse ? = cur-val [
          set cur-freq cur-freq + 1
        ]
        [
          set freq-distrib fput (list cur-val cur-freq) freq-distrib
          plotxy (log cur-val 10) (log cur-freq 10)
          set cur-val ?
          set cur-freq 1
        ]
      ]
      plotxy (log cur-val 10) (log cur-freq 10)
      set freq-distrib fput (list cur-val cur-freq) freq-distrib
      
      set-current-plot "Innovation Sizes"
      set-plot-x-range 0 (1 + max innov-sizes)
      histogram innov-sizes
    ]
    set num-recent-changes num-changes
    set deadlocked (num-changes = 0)
    set num-changes 0
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to test-time
  setup
  let start-time timer
  repeat 1000 [go]
  print (word "Time taken: " (timer - start-time))
end
@#$#@#$#@
GRAPHICS-WINDOW
279
10
689
441
-1
-1
4.0
1
10
1
1
1
0
1
0
1
0
99
0
99
0
0
1
ticks
30.0

SLIDER
5
143
177
176
Search-Radius-m
Search-Radius-m
1
20
3
1
1
NIL
HORIZONTAL

BUTTON
6
308
70
341
Setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
73
308
136
341
Go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
139
308
202
341
Go Once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
705
579
790
632
# Columns
1 + max-pxcor - min-pxcor
1
1
13

INPUTBOX
5
243
95
303
Max-ticks
5000
1
0
Number

INPUTBOX
98
243
202
303
Output-Every
100
1
0
Number

INPUTBOX
5
179
95
239
Search-Effort-E
0.05
1
0
Number

TEXTBOX
9
10
209
62
Percolation Model of Innovation
20
0.0
1

MONITOR
705
375
829
428
Mean BPF Height
mean-height
1
1
13

MONITOR
705
433
836
486
Mean Path Length
mean-pathlength
1
1
13

PLOT
934
392
1154
542
States
State
# Patches
0.0
4.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 1 -16777216 true "" ""

SLIDER
5
106
189
139
Chance-Possible-q
Chance-Possible-q
0
100
70
1
1
/ 100
HORIZONTAL

PLOT
705
10
1122
181
Progress
Time (ticks)
# Steps
0.0
1.0
0.0
1.0
true
true
"" ""
PENS
"BPF Height" 1.0 0 -13345367 true "" ""
"Path Length" 1.0 0 -2674135 true "" ""

PLOT
705
184
925
370
Innovation Sizes
Size
Frequency
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 1 -16777216 true "" ""

TEXTBOX
9
351
261
577
Technologies are in one of four states:\n0 (black) Impossible\n1 (white if not grey) Possible, but not yet discovered\n2 (yellow) Discovered, but not yet viable\n3 (pink if not green) Discovered and viable\n\nThose in green are discovered, viable, and at the best-practice frontier.\n\nThose in grey are possible, but will never be viable as they are cut off from the baseline by impossible technologies.
13
0.0
1

TEXTBOX
8
63
256
101
After Silverberg & Verspagen (2005)\nThis program (C) Christopher Watts, 2014.
13
0.0
1

PLOT
928
184
1123
370
Log-Log
Log Innovation Size
Log Frequency
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 2 -16777216 true "" ""

MONITOR
878
579
978
632
% Reachable
perc-reachable * 100
1
1
13

MONITOR
793
579
874
632
# Possible
num-possible
1
1
13

MONITOR
705
489
835
542
# Recent Changes
num-recent-changes
1
1
13

MONITOR
838
489
926
542
NIL
Deadlocked
17
1
13

MONITOR
98
180
225
233
Search Area Size
2 * search-radius-m * (search-radius-m + 1)
17
1
13

TEXTBOX
706
555
856
573
Current Grid:
13
0.0
1

@#$#@#$#@
# THE PERCOLATION MODEL OF INNOVATION

As described in Gerald Silverberg & Bart Verspagen (2005)

This program (C) Christopher Watts, 2014. See below for terms and conditions of use.

This program was developed for Chapter 7 of the book:

> Watts, Christopher and Gilbert, Nigel (2014) “Simulating Innovation: Computer-based Tools for Rethinking Innovation”. Cheltenham, UK and Northampton, MA, USA: Edward Elgar.


## HOW IT WORKS

Patches represent positions in technology space. Each column represents a technological niche or dimension. Height represents technological progress or improvement in that niche.

Technologies (patches) are in one of four states:  
0 Impossible (coloured black), excluded by nature  
1 Possible (white, if not grey), but not yet discovered  
2 Discovered (yellow), but not yet viable  
3 Viable (pink, if not green)  
In each column the highest viable technology forms part of the "best-practice frontier" (BPF) and is shaded green.

Initially all technologies are in state 0 (impossible) or in state 1 (possible), except for a base line that are in state 3 (viable). 

Each time tick, as a result of research, discoveries are made at random, somewhere among the possible technologies that are within some given search radius of the best-practice frontier (BPF). The BPF consists of the highest viable technologies in each dimension. Discovery results in a technology changing from state 1 to state 2. Technologies in state 0 cannot change state. Discovered technologies in state 2 can move to state 3 (viable) if and only if there is an unbroken chain of viable technologies linking that technology to the base line technologies.

An advances in height of the BPF in a dimension represents an innovation. The size of innovation is represented by the number of patch rows the BPF advances. Periodically a frequency distribution is plotted of the innovation sizes so far. Over time this may come to resemble a scale-free or power-law distribution, familiar from models of self-organised criticality (e.g. Per Bak's sandpile model). A scale-free frequency distribution will tend to form a linear trend when both axes have logarithmic scales (a "log-log plot").

Technologies which are possible but cannot be reached from the baseline by an unbroken chain of technologies of state >= 1 will never become viable. These are coloured grey.


## HOW TO USE IT

Choose q, the chance that each technology patches is initialised as possible rather than impossible.

Choose the size of the search radius, m. Search will be performed in all patches up to and including m steps away from a starting patch, where steps follow a von Neumann network architecture. (I.e. each patch has four neighbours: four up, down, left, and right.)

"Search-Effort-E" controls the chance of a discovery being made, along with the radius. Search effort must be shared out among all the technologies within the radius.

Click "Setup" to initialise the technology space.

Click "Go" to begin searching.

The simulation will run until "Go" is clicked again, or the number of time ticks has reached "Max-ticks".

Charts are plotted periodically, as determined by "Output-Every".

Also output are the mean height of the best-practice frontier, and the mean path length of the shortest paths connecting the BPF to the base line.


## THINGS TO NOTICE

Some technologies (coloured grey) may be "possible" at the start but cannot be reached from the baseline by an unbroken path of possible technologies. These technologies will never become "viable", even if discovered.

If the chance of possible technologies is too low, technological progress will come to a halt prematurely.

As well as noticing the emerging distribution of innovation sizes, look for how larger size innovations come about. Progress in one dimension can become blocked, until a path to a higher technology in that dimension is created through progress in nearby dimensions.

Some parameter values produce better approximations to a scale-free distribution than others.


## THINGS TO TRY

Explore the range of values of the two main parameters, q and m. When does the network of possible states form a single component? What is the BPF height and the mean path length after 5000 iterations?


## EXTENDING THE MODEL

See Silverberg & Verspagen (2007) for a much modified percolation model.

What if a different network architecture is used? E.g. replace all mention in the program of "neighbors4" (Von Neumann architecture) with "neighbors" (Moorean architecture).

What if technology space (represented by the world) does not wrap around horizontally?


## RELATED MODELS

See in particular other papers by Silverberg and Verspagen (especially 2007), for their own variations on the percolation model of innovation.

The properties of percolation grids have been much studied within statistical physics.

Self-organised critical phenomena are known for their tendency towards scale-free frequency distributions of sizes. See in particular the sandpiles model in Per Bak's book "How nature works".

There have been various models of technological evolution and knowledge dynamics, e.g. Ahrweiler, Pyka & Gilbert's SKIN model.


## CREDITS AND REFERENCES

Silverberg, G & B Verspagen (2005) "A percolation model of innovation in complex technology spaces". Journal of Economic Dynamics & Control, 29, 225-244.

Silverberg, G & B Verspagen (2007) "Self-organization of R&D search in complex technology spaces". Journal of Economic Interaction & Coordination, 2, 195-210.


## OUR TERMS AND CONDITIONS OF USE

This program was developed for the book:

Watts, Christopher and Gilbert, Nigel (2014) “Simulating Innovation: Computer- based Tools for Rethinking Innovation”. Cheltenham, UK and Northampton, MA, USA: Edward Elgar.

If you use this program in your work, please cite the book, as well as giving the URL for the website from which you downloaded the program and the date on which you downloaded it. A suitable form of citation for the program is:

Watts, Christopher (2014) “Name-of-file”. Retrieved 31 January 2014 from http://www.simian.ac.uk/resources/models/simulating-innovation.

This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation. See http://www.gnu.org/licenses/ for more details. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 

Those wishing to make commercial use of the program should contact the book’s authors to discuss terms.

This program has been designed to be run using NetLogo version 5, which can be obtained from http://ccl.northwestern.edu/netlogo/

@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
0
Rectangle -7500403 true true 151 225 180 285
Rectangle -7500403 true true 47 225 75 285
Rectangle -7500403 true true 15 75 210 225
Circle -7500403 true true 135 75 150
Circle -16777216 true false 165 76 116

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.0.4
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment-MeanHeight" repetitions="10" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>timer</metric>
    <metric>num-possible</metric>
    <metric>num-reachable</metric>
    <metric>perc-reachable</metric>
    <metric>num-columns</metric>
    <metric>num-recent-changes</metric>
    <metric>mean-height</metric>
    <metric>mean-pathlength</metric>
    <metric>deadlocked</metric>
    <metric>count patches with [(pycor = max-pycor) and reachable]</metric>
    <metric>array:to-list state-freq</metric>
    <metric>freq-distrib</metric>
    <steppedValueSet variable="Chance-Possible-q" first="50" step="2" last="75"/>
    <steppedValueSet variable="Search-Radius-m" first="1" step="1" last="20"/>
    <enumeratedValueSet variable="Search-Effort-E">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Max-ticks">
      <value value="5000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Output-Every">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 1.0 0.0
0.0 1 1.0 0.0
0.2 0 1.0 0.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
