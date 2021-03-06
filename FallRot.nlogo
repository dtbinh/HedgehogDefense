__includes ["libCommon.nls" "libCombatModel.nls" "libBridgeModel.nls"]

;We make use of arrays in the bridge model
extensions [array]

globals [
  HedgehogDepth
  CheckRange CheckAngle
]

; Executed when the user click on the 'Setup' button
to setup
  ifelse (Model = "Historical Reset") [
    set CrossingChannel 22
    set CrossingAbbeville 49
    set CrossingAmiens 72
    set CrossingBray 25
    set CrossingPeronne 44
    set TimeScale 0.5
    set FrenchForceRetreat 0.5
    set GermanReorgPause 12
    set CrossingRate 3000
    set HoursBetweenBridges 12
    set MaxBridges 5
  ][
  ifelse (Model = "(Retreat) No Retreat Broadcast") [
    set RetreatBroadcast false
    set BroadcastRange 0
    set RetreatScalar 0
  ][
  ifelse (Model = "(Retreat) Hold Ground Behavior") [
    set RetreatBroadcast true
    set BroadcastRange 8
    set RetreatScalar 1
  ][
  if (Model = "(Retreat) Panicked Behavior") [
    set RetreatBroadcast true
    set BroadcastRange 5
    set RetreatScalar 1.8
  ]]]]
  
  setup-Common      ;Procedure found in libCommon. Initializes various system constants.
  setup-CombatModel ;Procedure found in libCombatModel. Initializes attrition coefficients.
  setup-BridgeModel ;Procedure found in libBridgeModel. Initializes staging coordinates.
  
  set HedgehogDepth (5 / MapScale)
  set CheckRange (BroadcastRange / MapScale) 
  set CheckAngle 30
  
  setup-patches     ;Display the background
  setup-units       ;Place brigades and set their attributes.
end

to setup-patches
 import-drawing "Map.png" ;Sets up the map background.
end

to setup-units
  ;Creates German brigades, sets their color red, makes them face towards the French, and places them on the map.
  create-units (188) [
    c_writeUnit GermanInfBrigade
    set heading 225
    set color 15
    set state s_RESERVE
    set destinationNum -1
    place-germans                ;Procedure found in libBridgeModel. Places German brigades in random clusters.
  ]
  ;Creates German tank brigades, sets their color red, makes them face towards the French, and places them on the map.
  create-units (24) [
    c_writeUnit GermanPzrBrigade
    set heading 225  
    set color 15
    set state s_RESERVE
    set destinationX -1
    set destinationY -1
    set destinationNum -1
    place-germans                ;Procedure found in libBridgeModel. Places German brigades in random clusters.
  ]
  
  ;Creates French brigades, sets their color blue, makes them face towards the Germans.
  create-units (76)[
    c_writeUnit FrenchInfBrigade
    set color 95
    set state s_P_DEFENSE
  ]
  ;Creates French light brigades, sets their color blue, makes them face towards the Germans.
  create-units (12) [
    c_writeUnit FrenchCavBrigade
    set color 95
    set state s_P_DEFENSE
  ]
  ;Creates French light brigades, sets their color blue, makes them face towards the Germans.
  create-units (12) [
    c_writeUnit FrenchDLMBrigade
    set color 95
    set state s_P_DEFENSE
  ]
  ;Creates French armored brigades, sets their color blue, makes them face towards the Germans.
  create-units (12) [
    c_writeUnit FrenchDCrBrigade
    set color 95
    set state s_P_DEFENSE
  ]
  
  ; Places the French in a checkerboard pattern
  let leftPatch patch 110 472                 ; our vertices
  let v1Patch patch 377 298
  let v2Patch patch 581 335
  let rightPatch patch 575 300
 
  let lToV1 0                                 ; calculate the angles and spacing
  let lToV1_distance 0
  ask leftPatch [
    set lToV1 towards v1Patch
    set lToV1_distance distance v1Patch
  ]
  let v1ToV2 0
  let v1ToV2_distance 0
  ask v1Patch [
    set v1ToV2 towards v2Patch
    set v1ToV2_distance distance v2Patch
  ]
  
  let totalUnits count units with [allegiance = FRENCH]
  let distancePerUnit ((lToV1_distance + v1ToV2_distance) / totalUnits)
  
  let i 0                                   ;deploy along those vertices, staggering odd units back a row
  let depth 5                               ;in km
  let leg 0
  let anchorPatch leftPatch
  let anchorAngle lToV1
  let anchorHeading 43
  let startPatch 0
  ask units with [allegiance = FRENCH] [
    ask anchorPatch [ set startPatch patch-at-heading-and-distance anchorAngle (distancePerUnit * i) ]
    set beginRow 0
    if (i mod 2 != 0) [
      ask startPatch [ set startPatch patch-at-heading-and-distance (anchorAngle + 90) HedgehogDepth ]
      set beginRow nobody
    ]
    ifelse (leg = 0 and [pxcor] of startPatch > [pxcor] of v1Patch) [
      set i 0
      set anchorPatch v1Patch
      set anchorAngle v1ToV2
      set anchorHeading 0
      set leg 1
    ] [
      move-to startPatch
      set heading anchorHeading
      set beginHeading heading
      set i (i + 1)
    ]
  ]
end

;This procedure is called when the user presses the 'Go' button.
to go
  let validUnits units with [effectiveness > 0]
  let GermanUnits validUnits with [allegiance = GERMAN]
  let FrenchUnits validUnits with [allegiance = FRENCH]

  ask DirectFiring [ set hidden? true ]       ;Still want to store links, but don't want to confuse by displaying as units move
  ask IndirectFiring [ set hidden? true ]
  
  ;Movement
  ask GermanUnits [
    if (state = s_RESERVE or state = s_Q_BRIDGE or state = s_ON_BRIDGE) [
      selectBridge ;Procedure found in libBridgeModel. Initializes destinations of the German brigades before the bridge crossing takes place.
      crossBridge ;Procedure found in libBridgeModel. Logic for the German brigades crossing the bridge.
    ]
  ]
  ask validUnits [ move ]

  clear-links                                 ;Clear all direct & indirect fire links for the new tick

  let combatUnits (validUnits with [state != s_RETREAT and state != s_ROUTE])
  ;Combat
  ask combatUnits [ cm_declareTarget ]        ;Everyone marks targets they'd like to fire at
  ask combatUnits [ cm_attritTargets ]        ;Each unit attrits all the targets that marked it + its target(s)
  ask combatUnits [ cm_realizeAttrition ]     ;Everyone updates themselves with the attrition dealt to them

  ;Bridge building
  if (numBridges < MaxBridges and ticks > (HoursBetweenBridges / TimeScale * numBridges)) [
    set numBridges numBridges + 1             ;Add another bridge at each crossing after hoursBetweenBridgeheads has passed
  ]

  ;If someone left the simulation on, stop it eventually...
  if (ticks >= 42800) [ stop ]
  if (count units with [allegiance = FRENCH and effectiveness > 0] < 2) [ stop ]
  
  tick
end


to move
;===================.
;== FORCE RETREAT ===
;==================='
  if (state != s_RETREAT) [
    let forceRetreat false
    ifelse (allegiance = FRENCH) [
      if (effectiveness - pressure <= beginEffectiveness - FrenchForceRetreat) [ set forceRetreat true ]
    ] [
      if (effectiveness - pressure <= beginEffectiveness - GermanForceRetreat) [ set forceRetreat true ]
    ]
    if (forceRetreat) [
      set beginState state                                            ; save state
      if ( beginState = s_P_DEFENSE ) [ set beginState s_DEFENSE ]    ; as unit can't prepare a new defensive position quickly enough
      set state s_RETREAT
      if (RetreatBroadcast) [ broadcastPressure ]
      set isNewState? true
    ]
  ]
  
  ifelse (allegiance = GERMAN) [
;=====================.
;== GERMAN BEHAVIOR ===
;====================='
    ifelse (state = s_OVR_BRIDGE) [                ;If just crossed the bridge...
      set state s_ATTACK
      set curSpeed maxSpeed * 0.8                  ;  controlled attack, so slow down slightly
    ][
    ifelse (state = s_RETREAT) [
      ifelse (isNewState?) [
        set reorgTimer (GermanReorgPause / TimeScale)
        set isNewState? false
      ] [
        set reorgTimer (reorgTimer - 1)
        if (reorgTimer = 0) [                        ;consider units reorganized and ready to attack
          set targetPatch nobody                     ;  clear my move target
          set state beginState                       ;  restore my state
          set beginState nobody
          set beginEffectiveness effectiveness       ;  store at what effectiveness I started here
          set pressure 0
        ]
      ]
    ][
    if (state = s_ATTACK or state = s_B_ATTACK) [  ;If attacking...
      let nearestEnemy nobody
      let dTargets count out-directFire-neighbors
      ifelse (dTargets > 0) [                      ;  ...and we currently have a target, stick with it
        if (dTargets != 1) [error "In move, this unit reported having more than one direct target."] ;DEBUG
        set nearestEnemy one-of out-directFire-neighbors
      ] [
        set nearestEnemy c_nearestAvailEnemy       ;  ...otherwise, find the nearest enemy that isn't already surrounded
        if (nearestEnemy = nobody) [stop]
      ]
      let enemyDistance distance nearestEnemy
      
      ifelse (enemyDistance > curDRange) [         ;  close to direct-fire weapons range if not there
        face nearestEnemy
        ifelse (enemyDistance - curDRange > curSpeed) [  ;  if won't arrive at enemy this tick, curSpeed ahead
          c_move curSpeed
        ] [
          c_move (enemyDistance - curDRange)             ;  else, approach just shy of the enemy (for visual distinction)
        ]
      ] [                                          ;  otherwise, let me randomly shift about the enemy if he's stationary
        if ([state] of nearestEnemy = s_P_DEFENSE) [
          let myHeading nobody
          ifelse (xcor = [xcor] of nearestEnemy and ycor = [ycor] of nearestEnemy) [
            set myHeading (random 360)
          ] [
          ask nearestEnemy [ set myHeading towards myself ]
          ]
          let randomShift ((random 46) - 23)
          set myHeading (myHeading + randomShift)
          
          let myTarget nobody
          ask nearestEnemy [ set myTarget patch-at-heading-and-distance myHeading curDRange ]
          if (myTarget = nobody) [stop]
          move-to myTarget
          face nearestEnemy
        ]
      ]
    ]]]
  ] [
    let nearestEnemy c_nearestEnemy             ;Procedure found in libCommon. Returns the nearest opponent.
    if (nearestEnemy = nobody) [stop]           ;FIXME should use something like c_nearestAvilEnemy, but oscillates currently
    let enemyDistance distance nearestEnemy
    
    
;=====================.
;== FRENCH BEHAVIOR ===
;====================='
    ifelse (state != s_RETREAT) [                    ;  If not retreating...
      if (enemyDistance < 2 * curIRange) [face nearestEnemy]
    ][
    if (state = s_RETREAT) [                         ;  If retreating...
      ifelse isNewState? [                           ;initialization for retreat behavior
        set isNewState? false
        let currentPatch patch-here
        ifelse (beginRow != nobody) [
          set targetPatch patch-at-heading-and-distance ((beginHeading + 180) mod 360) HedgehogDepth
          set beginRow nobody
        ] [
          set targetPatch patch-at-heading-and-distance ((beginHeading + 180) mod 360) (8 / MapScale)
        ]
        if (targetPatch = nobody) [                  ;nowhere to retreat, stand and fight
          set heading beginHeading
          set state beginState
          set beginState nobody
          set beginEffectiveness effectiveness
          set pressure 0
          stop
        ]
        face targetPatch
      ] [
        if (targetPatch = nobody) [stop]
        ifelse (distance targetPatch > curSpeed) [
          face targetPatch
          c_move curSpeed                            ;if we won't arrive at target this tick...
        ] [
          move-to targetPatch                        ;if we will arrive at target this tick...
          set heading beginHeading
          set targetPatch nobody                     ;  clear my move target
          set state beginState                       ;  restore my state
          set beginState nobody
          set beginEffectiveness effectiveness       ;  store at what effectiveness I started here
          set pressure 0
        ]
      ]
    ]]
  ]
end

to broadcastPressure
  let savedHeading heading
  let mySide units with [allegiance = [allegiance] of myself]
  let myForceRetreat -1
  ifelse (allegiance = GERMAN) [ set myForceRetreat GermanForceRetreat ]
  [ set myForceRetreat FrenchForceRetreat ]
  
  set heading ((beginHeading + 90) mod 360)             ;locate units to my right
  let myRight mySide in-cone CheckRange CheckAngle
  set myRight myRight with [self != myself]             ;  remove myself from resulting set
  
  set heading ((beginHeading - 90) mod 360)             ;locate units to my left
  let myLeft mySide in-cone CheckRange CheckAngle
  set myLeft myLeft with [self != myself]              
  
  ask myRight [
    let newPressure ((1 - (distance myself / CheckRange)) * myForceRetreat * RetreatScalar)
    if (newPressure > pressure) [ set pressure newPressure ]
  ]
  ask myLeft [
    let newPressure ((1 - (distance myself / CheckRange)) * myForceRetreat * RetreatScalar)
    if (newPressure > pressure) [ set pressure newPressure ]
  ]
  
  set heading savedHeading
end
@#$#@#$#@
GRAPHICS-WINDOW
435
9
1093
688
-1
-1
1.013
1
4
1
1
1
0
0
0
1
0
639
0
639
0
0
1
ticks
30.0

BUTTON
226
13
293
46
NIL
Setup
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
15
67
78
100
NIL
Go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
314
13
396
58
NIL
Ticks
0
1
11

SLIDER
15
152
186
185
CrossingAbbeville
CrossingAbbeville
0
212
49
1
1
NIL
HORIZONTAL

SLIDER
15
196
186
229
CrossingAmiens
CrossingAmiens
0
212
72
1
1
NIL
HORIZONTAL

SLIDER
16
240
186
273
CrossingBray
CrossingBray
0
212
25
1
1
NIL
HORIZONTAL

SLIDER
17
285
186
318
CrossingPeronne
CrossingPeronne
0
212
44
1
1
NIL
HORIZONTAL

SLIDER
14
109
186
142
CrossingChannel
CrossingChannel
0
212
22
1
1
NIL
HORIZONTAL

PLOT
15
393
394
559
Forces
Time
Soldiers
0.0
250.0
0.0
860000.0
true
true
"" "if(plotForces = true)[\n  let numGerman 0\n  let numFrench 0\n  ask turtles[\n    ifelse (allegiance = GERMAN) [\n      set numGerman numGerman + curInf + curAT + curArt + curTanks\n    ] [\n      set numFrench numFrench + curInf + curAT + curArt + curTanks\n    ]\n]\nset-current-plot-pen \"French\"\nplot numFrench\nset-current-plot-pen \"German\"\nplot numGerman\n]"
PENS
"German" 1.0 0 -2674135 true "" ""
"French" 1.0 0 -13791810 true "" ""

SWITCH
17
328
123
361
PlotForces
PlotForces
0
1
-1000

MONITOR
227
328
394
381
Number of Bridgeheads
numBridges
0
1
13

SWITCH
267
612
393
645
FireAnimation
FireAnimation
0
1
-1000

SLIDER
195
109
395
142
FrenchForceRetreat
FrenchForceRetreat
0
1
0.5
0.01
1
attrition
HORIZONTAL

SLIDER
195
241
394
274
HoursBetweenBridges
HoursBetweenBridges
1
72
12
1
1
NIL
HORIZONTAL

SLIDER
195
285
393
318
MaxBridges
MaxBridges
0
10
5
1
1
NIL
HORIZONTAL

SLIDER
195
197
394
230
CrossingRate
CrossingRate
0
4000
3000
100
1
NIL
HORIZONTAL

SLIDER
194
66
396
99
TimeScale
TimeScale
0.05
1
0.5
0.05
1
hours per tick
HORIZONTAL

SWITCH
267
570
394
603
MoveAnimation
MoveAnimation
0
1
-1000

SLIDER
16
656
394
689
RetreatScalar
RetreatScalar
0
2
0
0.1
1
* ForceRetreat * Distance / BroadcastRange
HORIZONTAL

SWITCH
16
570
170
603
RetreatBroadcast
RetreatBroadcast
1
1
-1000

SLIDER
16
613
170
646
BroadcastRange
BroadcastRange
0
30
0
1
1
km
HORIZONTAL

SLIDER
195
153
395
186
GermanReorgPause
GermanReorgPause
1
24
12
0.25
1
hours
HORIZONTAL

CHOOSER
16
13
206
58
Model
Model
"No Slider Changes on Setup" "Historical Reset" "(Retreat) No Retreat Broadcast" "(Retreat) Hold Ground Behavior" "(Retreat) Panicked Behavior"
2

@#$#@#$#@
## WHAT IS IT?

This is an agent-based simulation that represents the first week of Fall Rot in the Battle of France of World War II. The Germans (in red), deploying the Blitzkrieg tactic, attack fortified French positions, "hedgehogs," (in blue) across the river. This scenario opens up interesting tactical questions of how the allocation and speed of the German bridge crossing impacts attrition. Each arrow represents a brigade.

## HOW IT WORKS

German brigades will move towards French static positions and both sides engage each other with direct and indirect fire (based on the distance). The Lanchester model of attrition was used. Retreat will start once the number of soldiers in a brigade reaches a certain pre-defined level.

## HOW TO USE IT

The Model choice is used to toggle between various preset selections, each of which are loaded by then pressing the Setup button. If no slider changes are desired, then the Model choice should be 'No Slider Changes on Setup' when Setup is clicked.

Setup will then place brigades in their initial positions, where the French positions are in a checkerboard pattern. The Go button will make the simulation run.

A variety of adjustments may be made to the model, all of which should be set before pressing the Setup button.

The disposition of the attacking German forces amongst the available bridgeheads may be changed (historically accurate total brigade count will be enforced). The TimeScale of each tick may be altered. Several retreat and bridge variables may be tweaked. Plotting and animations may be toggled on and off. Lastly, several settings regarding how retreat broadcasts (if turned on) spread through brigades are available.

## THINGS TO NOTICE

The 'Forces' plot will give insight to the attrition dynamics based on the parameters the user has chosen to set.

## THINGS TO TRY

The analyst can choose to vary the bridge-crossing mobility of the German forces and its impact on attrition by enabling the 'PlotForces' switch.

## EXTENDING THE MODEL

Mobility could be made more accurate by taking into account human factor studies.
The hedgehog defense could be analyzed in more depth and in isolation in a submodel at the scope of individual soldiers and obstacles (urban warfare).
Command and control features could be added to make brigades act with higher intelligence and communication. 

## NETLOGO FEATURES

This simulation makes use of includes.

## RELATED MODELS

There don't appear to be any military models in the NetLogo library.

## CREDITS AND REFERENCES

INTA 6742 Project
Team 4 - Operation Fall Rot
Manuel Aguilar
John Bieniek
Ethan Brown
Philip Pecher
David Richards
Lucas Smith
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

ant
true
0
Polygon -7500403 true true 136 61 129 46 144 30 119 45 124 60 114 82 97 37 132 10 93 36 111 84 127 105 172 105 189 84 208 35 171 11 202 35 204 37 186 82 177 60 180 44 159 32 170 44 165 60
Polygon -7500403 true true 150 95 135 103 139 117 125 149 137 180 135 196 150 204 166 195 161 180 174 150 158 116 164 102
Polygon -7500403 true true 149 186 128 197 114 232 134 270 149 282 166 270 185 232 171 195 149 186
Polygon -7500403 true true 225 66 230 107 159 122 161 127 234 111 236 106
Polygon -7500403 true true 78 58 99 116 139 123 137 128 95 119
Polygon -7500403 true true 48 103 90 147 129 147 130 151 86 151
Polygon -7500403 true true 65 224 92 171 134 160 135 164 95 175
Polygon -7500403 true true 235 222 210 170 163 162 161 166 208 174
Polygon -7500403 true true 249 107 211 147 168 147 168 150 213 150

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

bee
true
0
Polygon -1184463 true false 151 152 137 77 105 67 89 67 66 74 48 85 36 100 24 116 14 134 0 151 15 167 22 182 40 206 58 220 82 226 105 226 134 222
Polygon -16777216 true false 151 150 149 128 149 114 155 98 178 80 197 80 217 81 233 95 242 117 246 141 247 151 245 177 234 195 218 207 206 211 184 211 161 204 151 189 148 171
Polygon -7500403 true true 246 151 241 119 240 96 250 81 261 78 275 87 282 103 277 115 287 121 299 150 286 180 277 189 283 197 281 210 270 222 256 222 243 212 242 192
Polygon -16777216 true false 115 70 129 74 128 223 114 224
Polygon -16777216 true false 89 67 74 71 74 224 89 225 89 67
Polygon -16777216 true false 43 91 31 106 31 195 45 211
Line -1 false 200 144 213 70
Line -1 false 213 70 213 45
Line -1 false 214 45 203 26
Line -1 false 204 26 185 22
Line -1 false 185 22 170 25
Line -1 false 169 26 159 37
Line -1 false 159 37 156 55
Line -1 false 157 55 199 143
Line -1 false 200 141 162 227
Line -1 false 162 227 163 241
Line -1 false 163 241 171 249
Line -1 false 171 249 190 254
Line -1 false 192 253 203 248
Line -1 false 205 249 218 235
Line -1 false 218 235 200 144

bird1
false
0
Polygon -7500403 true true 2 6 2 39 270 298 297 298 299 271 187 160 279 75 276 22 100 67 31 0

bird2
false
0
Polygon -7500403 true true 2 4 33 4 298 270 298 298 272 298 155 184 117 289 61 295 61 105 0 43

boat1
false
0
Polygon -1 true false 63 162 90 207 223 207 290 162
Rectangle -6459832 true false 150 32 157 162
Polygon -13345367 true false 150 34 131 49 145 47 147 48 149 49
Polygon -7500403 true true 158 33 230 157 182 150 169 151 157 156
Polygon -7500403 true true 149 55 88 143 103 139 111 136 117 139 126 145 130 147 139 147 146 146 149 55

boat2
false
0
Polygon -1 true false 63 162 90 207 223 207 290 162
Rectangle -6459832 true false 150 32 157 162
Polygon -13345367 true false 150 34 131 49 145 47 147 48 149 49
Polygon -7500403 true true 157 54 175 79 174 96 185 102 178 112 194 124 196 131 190 139 192 146 211 151 216 154 157 154
Polygon -7500403 true true 150 74 146 91 139 99 143 114 141 123 137 126 131 129 132 139 142 136 126 142 119 147 148 147

boat3
false
0
Polygon -1 true false 63 162 90 207 223 207 290 162
Rectangle -6459832 true false 150 32 157 162
Polygon -13345367 true false 150 34 131 49 145 47 147 48 149 49
Polygon -7500403 true true 158 37 172 45 188 59 202 79 217 109 220 130 218 147 204 156 158 156 161 142 170 123 170 102 169 88 165 62
Polygon -7500403 true true 149 66 142 78 139 96 141 111 146 139 148 147 110 147 113 131 118 106 126 71

box
true
0
Polygon -7500403 true true 45 255 255 255 255 45 45 45

butterfly1
true
0
Polygon -16777216 true false 151 76 138 91 138 284 150 296 162 286 162 91
Polygon -7500403 true true 164 106 184 79 205 61 236 48 259 53 279 86 287 119 289 158 278 177 256 182 164 181
Polygon -7500403 true true 136 110 119 82 110 71 85 61 59 48 36 56 17 88 6 115 2 147 15 178 134 178
Polygon -7500403 true true 46 181 28 227 50 255 77 273 112 283 135 274 135 180
Polygon -7500403 true true 165 185 254 184 272 224 255 251 236 267 191 283 164 276
Line -7500403 true 167 47 159 82
Line -7500403 true 136 47 145 81
Circle -7500403 true true 165 45 8
Circle -7500403 true true 134 45 6
Circle -7500403 true true 133 44 7
Circle -7500403 true true 133 43 8

circle
false
0
Circle -7500403 true true 35 35 230

person
false
0
Circle -7500403 true true 155 20 63
Rectangle -7500403 true true 158 79 217 164
Polygon -7500403 true true 158 81 110 129 131 143 158 109 165 110
Polygon -7500403 true true 216 83 267 123 248 143 215 107
Polygon -7500403 true true 167 163 145 234 183 234 183 163
Polygon -7500403 true true 195 163 195 233 227 233 206 159

sheep
false
15
Rectangle -1 true true 90 75 270 225
Circle -1 true true 15 75 150
Rectangle -16777216 true false 81 225 134 286
Rectangle -16777216 true false 180 225 238 285
Circle -16777216 true false 1 88 92

spacecraft
true
0
Polygon -7500403 true true 150 0 180 135 255 255 225 240 150 180 75 240 45 255 120 135

thin-arrow
true
0
Polygon -7500403 true true 150 0 0 150 120 150 120 293 180 293 180 150 300 150

truck-down
false
0
Polygon -7500403 true true 225 30 225 270 120 270 105 210 60 180 45 30 105 60 105 30
Polygon -8630108 true false 195 75 195 120 240 120 240 75
Polygon -8630108 true false 195 225 195 180 240 180 240 225

truck-left
false
0
Polygon -7500403 true true 120 135 225 135 225 210 75 210 75 165 105 165
Polygon -8630108 true false 90 210 105 225 120 210
Polygon -8630108 true false 180 210 195 225 210 210

truck-right
false
0
Polygon -7500403 true true 180 135 75 135 75 210 225 210 225 165 195 165
Polygon -8630108 true false 210 210 195 225 180 210
Polygon -8630108 true false 120 210 105 225 90 210

turtle
true
0
Polygon -7500403 true true 138 75 162 75 165 105 225 105 225 142 195 135 195 187 225 195 225 225 195 217 195 202 105 202 105 217 75 225 75 195 105 187 105 135 75 142 75 105 135 105

wolf
false
0
Rectangle -7500403 true true 15 105 105 165
Rectangle -7500403 true true 45 90 105 105
Polygon -7500403 true true 60 90 83 44 104 90
Polygon -16777216 true false 67 90 82 59 97 89
Rectangle -1 true false 48 93 59 105
Rectangle -16777216 true false 51 96 55 101
Rectangle -16777216 true false 0 121 15 135
Rectangle -16777216 true false 15 136 60 151
Polygon -1 true false 15 136 23 149 31 136
Polygon -1 true false 30 151 37 136 43 151
Rectangle -7500403 true true 105 120 263 195
Rectangle -7500403 true true 108 195 259 201
Rectangle -7500403 true true 114 201 252 210
Rectangle -7500403 true true 120 210 243 214
Rectangle -7500403 true true 115 114 255 120
Rectangle -7500403 true true 128 108 248 114
Rectangle -7500403 true true 150 105 225 108
Rectangle -7500403 true true 132 214 155 270
Rectangle -7500403 true true 110 260 132 270
Rectangle -7500403 true true 210 214 232 270
Rectangle -7500403 true true 189 260 210 270
Line -7500403 true 263 127 281 155
Line -7500403 true 281 155 281 192

wolf-left
false
3
Polygon -6459832 true true 117 97 91 74 66 74 60 85 36 85 38 92 44 97 62 97 81 117 84 134 92 147 109 152 136 144 174 144 174 103 143 103 134 97
Polygon -6459832 true true 87 80 79 55 76 79
Polygon -6459832 true true 81 75 70 58 73 82
Polygon -6459832 true true 99 131 76 152 76 163 96 182 104 182 109 173 102 167 99 173 87 159 104 140
Polygon -6459832 true true 107 138 107 186 98 190 99 196 112 196 115 190
Polygon -6459832 true true 116 140 114 189 105 137
Rectangle -6459832 true true 109 150 114 192
Rectangle -6459832 true true 111 143 116 191
Polygon -6459832 true true 168 106 184 98 205 98 218 115 218 137 186 164 196 176 195 194 178 195 178 183 188 183 169 164 173 144
Polygon -6459832 true true 207 140 200 163 206 175 207 192 193 189 192 177 198 176 185 150
Polygon -6459832 true true 214 134 203 168 192 148
Polygon -6459832 true true 204 151 203 176 193 148
Polygon -6459832 true true 207 103 221 98 236 101 243 115 243 128 256 142 239 143 233 133 225 115 214 114

wolf-right
false
3
Polygon -6459832 true true 170 127 200 93 231 93 237 103 262 103 261 113 253 119 231 119 215 143 213 160 208 173 189 187 169 190 154 190 126 180 106 171 72 171 73 126 122 126 144 123 159 123
Polygon -6459832 true true 201 99 214 69 215 99
Polygon -6459832 true true 207 98 223 71 220 101
Polygon -6459832 true true 184 172 189 234 203 238 203 246 187 247 180 239 171 180
Polygon -6459832 true true 197 174 204 220 218 224 219 234 201 232 195 225 179 179
Polygon -6459832 true true 78 167 95 187 95 208 79 220 92 234 98 235 100 249 81 246 76 241 61 212 65 195 52 170 45 150 44 128 55 121 69 121 81 135
Polygon -6459832 true true 48 143 58 141
Polygon -6459832 true true 46 136 68 137
Polygon -6459832 true true 45 129 35 142 37 159 53 192 47 210 62 238 80 237
Line -16777216 false 74 237 59 213
Line -16777216 false 59 213 59 212
Line -16777216 false 58 211 67 192
Polygon -6459832 true true 38 138 66 149
Polygon -6459832 true true 46 128 33 120 21 118 11 123 3 138 5 160 13 178 9 192 0 199 20 196 25 179 24 161 25 148 45 140
Polygon -6459832 true true 67 122 96 126 63 144

@#$#@#$#@
NetLogo 5.0.3
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="end-reps" repetitions="10" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>repeat 160 [go]</go>
    <final>print-final-report</final>
    <timeLimit steps="42801"/>
    <metric>report-boys</metric>
    <metric>report-girls</metric>
    <metric>differenciation</metric>
    <metric>girls-beating-boys</metric>
    <enumeratedValueSet variable="attraction?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="intensity-of-aggression">
      <value value="0.1"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="population">
      <value value="4"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Count brigades against hoursbetweenbridges" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000"/>
    <metric>count turtles with [who &lt; 189 and  curInf &gt; 2750]</metric>
    <metric>count turtles with [who &lt; 189 and  curInf &lt; 2750 and curInf &gt; 1375]</metric>
    <metric>count turtles with [who &lt; 189 and  curInf &lt; 1375]</metric>
    <metric>count turtles with [who &lt; 288 and who &gt; 212 and curInf &gt; 1579]</metric>
    <metric>count turtles with [who &lt; 288 and who &gt; 212 and curInf &lt; 1579 and curInf &gt; 839]</metric>
    <metric>count turtles with [who &lt; 288 and who &gt; 212 and curInf &lt; 839]</metric>
    <enumeratedValueSet variable="MoveAnimation">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingPeronne">
      <value value="44"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingAbbeville">
      <value value="49"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="TimeScale">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingChannel">
      <value value="22"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="FrenchForceRetreat">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingAmiens">
      <value value="72"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="FireAnimation">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingRate">
      <value value="3000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="PlotForces">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingBray">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="MaxBridges">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="HoursBetweenBridges">
      <value value="4"/>
      <value value="12"/>
      <value value="24"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Count brigades against maxbridges" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000"/>
    <metric>count turtles with [who &lt; 189 and  curInf &gt; 2750]</metric>
    <metric>count turtles with [who &lt; 189 and  curInf &lt; 2750 and curInf &gt; 1375]</metric>
    <metric>count turtles with [who &lt; 189 and  curInf &lt; 1375]</metric>
    <metric>count turtles with [who &lt; 288 and who &gt; 212 and curInf &gt; 1579]</metric>
    <metric>count turtles with [who &lt; 288 and who &gt; 212 and curInf &lt; 1579 and curInf &gt; 839]</metric>
    <metric>count turtles with [who &lt; 288 and who &gt; 212 and curInf &lt; 839]</metric>
    <enumeratedValueSet variable="MoveAnimation">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingPeronne">
      <value value="44"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingAbbeville">
      <value value="49"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="TimeScale">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingChannel">
      <value value="22"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="FrenchForceRetreat">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingAmiens">
      <value value="72"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="FireAnimation">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingRate">
      <value value="3000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="PlotForces">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingBray">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="MaxBridges">
      <value value="2"/>
      <value value="5"/>
      <value value="8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="HoursBetweenBridges">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Count brigades against retreat" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000"/>
    <metric>count turtles with [who &lt; 189 and  curInf &gt; 2750]</metric>
    <metric>count turtles with [who &lt; 189 and  curInf &lt; 2750 and curInf &gt; 1375]</metric>
    <metric>count turtles with [who &lt; 189 and  curInf &lt; 1375]</metric>
    <metric>count turtles with [who &lt; 288 and who &gt; 212 and curInf &gt; 1579]</metric>
    <metric>count turtles with [who &lt; 288 and who &gt; 212 and curInf &lt; 1579 and curInf &gt; 839]</metric>
    <metric>count turtles with [who &lt; 288 and who &gt; 212 and curInf &lt; 839]</metric>
    <enumeratedValueSet variable="MoveAnimation">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingPeronne">
      <value value="44"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingAbbeville">
      <value value="49"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="TimeScale">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingChannel">
      <value value="22"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="FrenchForceRetreat">
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingAmiens">
      <value value="72"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="FireAnimation">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingRate">
      <value value="3000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="PlotForces">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingBray">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="MaxBridges">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="HoursBetweenBridges">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Count brigades against hoursbetweenbridges and maxbridges" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000"/>
    <metric>count turtles with [who &lt; 189 and  curInf &gt; 2750]</metric>
    <metric>count turtles with [who &lt; 189 and  curInf &lt; 2750 and curInf &gt; 1375]</metric>
    <metric>count turtles with [who &lt; 189 and  curInf &lt; 1375]</metric>
    <metric>count turtles with [who &lt; 288 and who &gt; 212 and curInf &gt; 1579]</metric>
    <metric>count turtles with [who &lt; 288 and who &gt; 212 and curInf &lt; 1579 and curInf &gt; 839]</metric>
    <metric>count turtles with [who &lt; 288 and who &gt; 212 and curInf &lt; 839]</metric>
    <enumeratedValueSet variable="MoveAnimation">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingPeronne">
      <value value="44"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingAbbeville">
      <value value="49"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="TimeScale">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingChannel">
      <value value="22"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="FrenchForceRetreat">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingAmiens">
      <value value="72"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="FireAnimation">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingRate">
      <value value="3000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="PlotForces">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CrossingBray">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="MaxBridges">
      <value value="1"/>
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="HoursBetweenBridges">
      <value value="4"/>
      <value value="24"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
