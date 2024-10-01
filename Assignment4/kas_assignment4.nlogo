extensions [table] ;extend this, if you want

breed [traders trader]
breed [producers producer]
breed [retailers retailer]

globals [
  productColorMapping ;hashmap
  products ; list
]

traders-own [
  messageQueue
  state               ; The current goal of the trader. E.g. MOVE_TO_PRODUCER
  product
  estimatedBuyPrice   ;maps each of the four products to an estimated buy-price
  estimatedSellPrice  ;maps mapping each of the four products to an estimated sell-price
  interactionRange
]

producers-own [
  messageQueue
  producedProduct
  stock
  sellPrice
  upperSL
  lowerSL
]

retailers-own [
  messageQueue
  stocks ;maps each product to a stock
  prices ;maps each product to a price
  upperSL
  lowerSL
]


TO SETUP
  clear-all

  set productColorMapping table:make ; maps each product to a color
  table:put productColorMapping "Fruit" green
  table:put productColorMapping "Meat" red
  table:put productColorMapping "Wine" yellow
  table:put productColorMapping "Dairy" violet
  table:put productColorMapping "None" black

  set products [ "Fruit" "Meat" "Wine" "Dairy"]

  ask patches [
    set pcolor white
  ]

  create-traders numberTraders
  ask traders [
    set messageQueue []
    setxy random-xcor random-ycor
    set state "CHOOSE_PRODUCT"
    set product "None"
    set interactionRange 1

    ;Initialize the estimated buy and sell prices somewhat randomly
    set estimatedBuyPrice table:make
    set estimatedSellPrice table:make
    foreach products [ [prd] ->
      table:put estimatedBuyPrice prd (random 50) + 25
      table:put estimatedSellPrice prd (random 50) + 25
    ]
    set color black
  ]

  create-retailers 1 [
    set messageQueue []
    setxy 0 0
    set heading 0
    set color black
    set shape "box"
    set size 2
    set upperSL 75
    set lowerSL 25

    set stocks table:make
    set prices table:make
    ;initialize the prices with 50 and the stocks to 75 for all products
    foreach products [ [prd] ->
      table:put prices prd 50
      table:put stocks prd 75
    ]
  ]
  create-producers 1 [
    set producedProduct "Fruit"
    setxy -15 -15
  ]
  create-producers 1 [
    set producedProduct "Meat"
    setxy -15 15
  ]
  create-producers 1 [
    set producedProduct "Wine"
    setxy 15 -15
  ]
  create-producers 1 [
    set producedProduct "Dairy"
    setxy 15 15
  ]
  ask producers [
    set messageQueue []
    set heading 0
    set color table:get productColorMapping producedProduct
    set shape "box"
    set size 1.5
    set upperSL 75
    set lowerSL 25
    set stock 100
    set sellPrice 50
  ]

  reset-ticks
end


TO GO
  ask traders [

    handleMessagesTrader

    (ifelse state = "CHOOSE_PRODUCT" [
      chooseProduct
    ] state = "MOVE_TO_PRODUCER" [
      moveToProducer
    ] state = "NEGOTIATE_BUY" [
      negotiateBuy
    ] state = "MOVE_TO_RETAILER" [
      moveToRetailer
    ] state = "NEGOTIATE_SALE" [
      negotiateSale
    ] state = "BUY_FROM_PRODUCER" [
      ; Just wait for confirmation messages mainly, or implement this yourself
    ] state = "SELL_TO_RETAILER" [
      ; Just wait for confirmation messages mainly, or implement this yourself
    ])
  ]

  ask producers [
    ; Update stock
    set stock stock + producersProduction
    if (stock > 100) [
      set stock 100
    ]

    ; Update prices
    if (stock > upperSL and sellPrice > 0) [
     set sellPrice sellPrice - 0.1
    ]
    if (stock < lowerSL) [
     set sellPrice sellPrice + 0.1
    ]

    handleMessagesProducer
  ]


  ask retailers [
    ; Update stock
    foreach products [ [prd] ->
      let newStock table:get stocks prd - stockDecreaseRetailer
      if (newStock < 0) [
        set newStock 0
      ]
      table:put stocks prd newStock

      ; Update prices
      let currentPrice table:get prices prd
      if (newStock < lowerSL) [
        table:put prices prd  (currentPrice + 0.1);
      ]
      if (newStock > upperSL and currentPrice > 0) [
        table:put prices prd (currentPrice - 0.1)
      ]
    ]

    handleMessagesRetailer
  ]

  tick
end

to chooseProduct
  ifelse chooseTheBest [
    ;; Iterate over estimated sell prize and buy prize and choose the most profitable.
    let highestProfit -100000000000000
    let bestProduct "None"
    foreach products [ [prd] ->
      let estimatedProfit table:get estimatedSellPrice prd - table:get estimatedBuyPrice prd
      if (estimatedProfit > highestProfit) [
        set highestProfit estimatedProfit
        set bestProduct prd
      ]
    ]
    set product bestProduct
  ] [
    ;****************************************
    ; IMPLEMENT THIS AS PART OF QUESTION 5
    ;****************************************
  ]
  set color table:get productColorMapping product
  if (product != "None") [
    set state "MOVE_TO_PRODUCER"
  ]
end

to moveToProducer
  let desiredProduct product
  if (desiredProduct != "None") [
    ifelse ( distance min-one-of producers with [producedProduct = desiredProduct] [ distance myself ] < interactionRange ) [
      set state "NEGOTIATE_BUY"
    ][
      set heading towards min-one-of producers with [producedProduct = desiredProduct] [distance myself]
      fd 1
    ]
  ]
end

to moveToRetailer
  set heading towards min-one-of retailers [distance myself]
  fd 1
  if ( distance  min-one-of retailers [ distance myself ] < interactionRange ) [
    set state "NEGOTIATE_SALE"
  ]
end

to negotiateBuy
  ; Assumptions: product of current turtle matches product of producer
  ; Assuming we are in the scope of the trader
  ; Assuming we are directly coming from chooseProduct and that we have not moved from the producer

  ; Select a producer to contact, this process can be fastened by making this an agent variable.
  let current-producer min-one-of producers with [producedProduct = [product] of myself] [ distance myself ]

  ; Send a message to request the price of the desired product
  let offerMessage createMessage "OFFER-TO-BUY" who product (table:get estimatedBuyPrice product);
  sendMessage current-producer offerMessage

  ;set state "BUY_FROM_PRODUCER"; We could let it wait for confimation but the worst case it does one
                                ; extra offer, which is not a problem since that can only result in
                                ; being set to MOVE_TO_RETAILER (and maybe a one-off problem with stock counting)
                                ; CHECK IF THIS IS STILL THE CASE
end

to negotiateSale
  ; Send a message to request the retailer's price of the held product

  ; get the retailer agent
  let theRetailer one-of retailers; There is only one retailer so this is sufficient for now

  let offerMessage createMessage "OFFER-TO-SELL" who product (table:get estimatedSellPrice product)
  sendMessage theRetailer offerMessage

end

to handleMessagesTrader
  ; Assuming a trader can only get one message
  foreach messageQueue [ [message] ->
    let messageContent table:get message "content"
    let messageSenderID table:get message "senderID"
    let messageProduct table:get message "product"
    let messageNumber table:get message "number"

    if messageProduct != product [
      print "error: accepted offer is a differt product"
    ]

    if messageContent = "BUY-OFFER-ACCEPTED" [
      let acceptedPrice messageNumber
      table:put estimatedBuyPrice product acceptedPrice
      set state "MOVE_TO_RETAILER"
    ]
    ; We could check what to do when offer is not accepted but
    ; we can since it is still in state "OFFER_BUY" it will
    ; just go through the process again

    if messageContent = "SELL-OFFER-ACCEPTED" [
      let acceptedPrice messageNumber
      table:put estimatedSellPrice product acceptedPrice
      set state "MOVE_TO_PRODUCER"
    ]
  ]

  ;empty the message queue
  set messageQueue []

end

to handleMessagesRetailer
  foreach messageQueue [ [message] ->
    let messageContent table:get message "content"
    let messageSenderID table:get message "senderID"
    let messageProduct table:get message "product"
    let messageNumber table:get message "number"; price that is offered in the message

    ifelse messageContent = "OFFER-TO-SELL" [
      ; Check whether offered price is low enough.
      ifelse messageNumber <= table:get prices messageProduct [
        ; If low enough buy the product, thus increase stock
        table:put stocks messageProduct ((table:get stocks messageProduct) + 1)
                        ; Confirm offer is accepted by retailer with given product and given price
        let confimationMessage (createMessage "SELL-OFFER-ACCEPTED" who messageProduct messageNumber)
        sendMessage (turtle messageSenderID) confimationMessage
      ][
                        ; Inform that message is rejected (THIS IS CURRENTLY NOT USED)
        let rejectionMessage (createMessage "SELL-OFFER-ACCEPTED" who messageProduct messageNumber)
        sendMessage (turtle messageSenderID) rejectionMessage
      ]
    ][
      print "Received unexpected message"
    ]
  ]
  ;empty the message queue
  set messageQueue []

end


to handleMessagesProducer
  ; Assume received messages are correct. They seem plausible.
  ; Assume stock is an int.
  ; Assume that message system between producer and trader works.
  foreach messageQueue [ [message] ->
    let messageContent table:get message "content"
    let messageSenderID table:get message "senderID"
    let messageProduct table:get message "product"
    let messageNumber table:get message "number"

    if messageProduct != producedProduct [
      print "Error: offered product does not match product of producer."
    ]

    ifelse messageContent = "OFFER-TO-BUY" [
      ifelse messageNumber >= sellPrice [
        set stock stock - 1
        let confirmationMessage (createMessage "BUY-OFFER-ACCEPTED" who producedProduct messageNumber)
        sendMessage (turtle messageSenderID) confirmationMessage
      ][
        let rejectionMessage (createMessage "BUY-OFFER-REJECTED" who producedProduct messageNumber)
        sendMessage (turtle messageSenderID) rejectionMessage
      ]
    ][
      print "Received unexpected message"
    ]
  ]
  ;empty the message queue
  set messageQueue []

end

to sentRejectionMessage

end


;code for messages

to-report createMessage [content senderID prd number]
  let message table:make
  table:put message "content" content
  table:put message "senderID" senderID
  table:put message "product" prd
  table:put message "number" number
  report message
end

to sendMessage [receiver message]
  ask receiver  [ set messageQueue lput  message messageQueue ]
end
@#$#@#$#@
GRAPHICS-WINDOW
273
10
662
400
-1
-1
12.3
1
10
1
1
1
0
0
0
1
-15
15
-15
15
1
1
1
ticks
5.0

BUTTON
10
12
90
65
NIL
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
100
12
179
66
NIL
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
186
12
266
66
tick
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

PLOT
668
10
1076
287
Stock Retailer
NIL
NIL
0.0
300.0
0.0
100.0
true
true
"" ""
PENS
"Meat" 1.0 0 -2674135 true "" "plot [ table:get stocks \"Meat\" ] of one-of retailers"
"Wine" 1.0 0 -1184463 true "" "plot [ table:get stocks \"Wine\" ] of one-of retailers"
"Fruit" 1.0 0 -10899396 true "" "plot [ table:get stocks \"Fruit\" ] of one-of retailers"
"Dairy" 1.0 0 -8630108 true "" "plot [ table:get stocks \"Dairy\" ] of one-of retailers"

SLIDER
51
157
222
190
stockDecreaseRetailer
stockDecreaseRetailer
0.1
5
0.5
0.1
1
NIL
HORIZONTAL

SLIDER
50
244
222
277
saleQuantity
saleQuantity
0
50
15.0
1
1
NIL
HORIZONTAL

PLOT
668
292
1076
532
Prices Retailer
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Meat" 1.0 0 -2674135 true "" "plot [ table:get prices \"Meat\" ] of one-of retailers"
"Wine" 1.0 0 -1184463 true "" "plot [ table:get prices \"Wine\" ] of one-of retailers"
"Fruit" 1.0 0 -10899396 true "" "plot [ table:get prices \"Fruit\" ] of one-of retailers"
"Dairy" 1.0 0 -8630108 true "" "plot [ table:get prices \"Dairy\" ] of one-of retailers"

SLIDER
50
123
222
156
producersProduction
producersProduction
0
5
1.9
0.1
1
NIL
HORIZONTAL

PLOT
1078
10
1500
287
Stock Producers
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Meat" 1.0 0 -2674135 true "" "plot [ stock ] of one-of producers with [producedProduct = \"Meat\"]"
"Wine" 1.0 0 -1184463 true "" "plot [ stock ] of one-of producers with [producedProduct = \"Wine\"]"
"Fruit" 1.0 0 -10899396 true "" "plot [ stock ] of one-of producers with [producedProduct = \"Fruit\"]"
"Dairy" 1.0 0 -8630108 true "" "plot [ stock ] of one-of producers with [producedProduct = \"Dairy\"]"

PLOT
1079
291
1502
534
Prices Producers
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Meat" 1.0 0 -2674135 true "" "plot [ sellPrice ] of one-of producers with [producedProduct = \"Meat\"]"
"Wine" 1.0 0 -1184463 true "" "plot [ sellPrice ] of one-of producers with [producedProduct = \"Wine\"]"
"Fruit" 1.0 0 -10899396 true "" "plot [ sellPrice ] of one-of producers with [producedProduct = \"Fruit\"]"
"Dairy" 1.0 0 -8630108 true "" "plot [ sellPrice ] of one-of producers with [producedProduct = \"Dairy\"]"

SLIDER
50
209
222
242
numberTraders
numberTraders
0
200
30.0
1
1
NIL
HORIZONTAL

SWITCH
51
283
223
316
chooseTheBest
chooseTheBest
0
1
-1000

MONITOR
275
427
357
472
Wine-Traders
count traders with [product = \"Wine\"]
0
1
11

MONITOR
359
427
439
472
Meat-Traders
count traders with [product = \"Meat\"]
17
1
11

MONITOR
444
428
523
473
Fruit-Traders
count traders with [product = \"Fruit\"]
17
1
11

MONITOR
525
428
609
473
Dairy-Traders
count traders with [product = \"Dairy\"]
17
1
11

@#$#@#$#@
## WHAT IS IT?



The centre tile is the locus of a retailer agent that wants
to buy four kinds of products: dairy, fruit, meat and wine. The corners of the
tile world are the locations of production, each represented by an agent. The
rest of the world is inhabited by a fixed number of trading agents.


	- Producers: 

Production representatives sell their product to the traders.
They have a price for their product and produce a certain amount (variable ’pro-
ducersProduction’) per time unit. Their stock is maximally 100 units. Prices
depend on stocks and sales. When their stock drops below 25 (variable ’low-
erSL’), they increase their price by 0.1 price unit. When it rises above 75
(variable ’upperSL’), they decrease their price by 0.1 price unit. In this way,
their price strategy aims at a stock between 25 and 75. The idea is that a high
stock level is a sign that the current price level is too high for the market and
that a low stock level is a sign of a price that is too low. In the simulation, the
producers are represented by squares at the corners. Their colour depicts the
product they are selling.

	- Retailer: 

The retailer buys products from the traders, hence also has a
price for each type of product. Stocks for each product drop by a certain
amount (variable ’stockDecreaseRetailer’, per time unit, as a representation
of the retailer’s selling to customers (not modelled further in the simulation)).
When his stocks are above 75 (variable ’upperSL’), he reduces his price by 0.1
price unit. When his stocks drop below 25 (variable ’lowerSL’), he increases his
price by 0.1 price unit. In the simulation, the retailer is the black square in the
center.

	- Traders: 

The traders move around in the world according to their current
plan: buy or sell. Traders have two price estimates for each type of product;
one for buying and one for selling. It is equal to the price used in the last suc-
cessful transaction, with random initialization. The traders have seven internal
states: CHOOSE PRODUCT, MOVE TO PRODUCER, NEGOTIATE BUY,
MOVE TO RETAILER, NEGOTIATE SALE, BUY FROM PRODUCER and
SELL TO RETAILER. They buy products at the production locations in fixed
quantities (variable ’saleQuantity’) and bring them to the retailer in order to
try to sell them.
CHOOSE PRODUCT
The trader decides which product to buy, based on the maximal difference
between his expected buy and sell price.
MOVE TO PRODUCER
The trader moves towards the producer.
NEGOTIATE BUY
The trader’s negotiation with a producer must be handled.
BUY FROM PRODUCER
The trader buys a product from a Producer.
MOVE TO RETAILER
The trader moves the retailer location.
NEGOTIATE SALE
the trader’s negotiation with the retailer must be handled.
SELL TO RETAILER
The trader sells a product to a Retailer.
Trading agents have the colour of the product they are trading in. The trader
can interact with a producer or retailer once they are close enough. (variable
’interactionRange’). If a trading agent meets a producer this way, a negotiation
ensues. When the trader’s current buying price estimate is equal or higher (i.e.,
when he has overestimated the buying price) and the offered price is below
their selling price estimate (i.e., when he thinks he can make money), the trader
accepts. The production representative accepts when the offer is above or equal
to their current price.
In case of a successful transaction, the trader uses the agreed price as the
new buying price estimate. When the exchange is not successful, the trader
increases their buying price for the product by 1 price unit and chooses a new
buying goal. When a trader arrives at the retailer’s location, a similar exchange
takes place. When a trader cannot sell the product he is carrying to the retailer,
he discards it (and adapts his selling price estimate for the product).
What the agents do not yet have, is a way of communicating which each
other, and hence, no way of negotiating sales. If you run the simulation as
provided, each trader will choose a buy goal, move to the appropriate producer,
and then stop. The idea is to have agents send messages to each other to
exchange information about their identity, products, buy and sell prices and so
forth. For this purpose, every agent has a ’messages’ queue, which all other
agents can ’deliver’ messages to (function sendMessage()). Every agent’s act
cycle starts by dealing with its received messages (function ’handleMessages’).
These functions have not yet been implemented.

## HOW TO USE IT

The SETUP button resets the time, prices and stocks. Traders are randomly distributed.

The GO button runs the simulation according to the rules
described above.

The 'producersProduction' slider controls the stock increase of the producers each tick. 

The 'stockDecreaseRetailer' slider controls the stock decrease of the retailer each tick.

The 'numberTraders' slider controls the amount of traders. 

The 'saleQuantity' slider controls the amount of products a trader can buy and sell at once. 


## THINGS TO NOTICE

Code is currently unfinished, because agents can not communicate with each other.

The plots on the right show the stocks and prices of the producers and retailer.
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
Polygon -1184463 true false 152 149 77 163 67 195 67 211 74 234 85 252 100 264 116 276 134 286 151 300 167 285 182 278 206 260 220 242 226 218 226 195 222 166
Polygon -16777216 true false 150 149 128 151 114 151 98 145 80 122 80 103 81 83 95 67 117 58 141 54 151 53 177 55 195 66 207 82 211 94 211 116 204 139 189 149 171 152
Polygon -7500403 true true 151 54 119 59 96 60 81 50 78 39 87 25 103 18 115 23 121 13 150 1 180 14 189 23 197 17 210 19 222 30 222 44 212 57 192 58
Polygon -16777216 true false 70 185 74 171 223 172 224 186
Polygon -16777216 true false 67 211 71 226 224 226 225 211 67 211
Polygon -16777216 true false 91 257 106 269 195 269 211 255
Line -1 false 144 100 70 87
Line -1 false 70 87 45 87
Line -1 false 45 86 26 97
Line -1 false 26 96 22 115
Line -1 false 22 115 25 130
Line -1 false 26 131 37 141
Line -1 false 37 141 55 144
Line -1 false 55 143 143 101
Line -1 false 141 100 227 138
Line -1 false 227 138 241 137
Line -1 false 241 137 249 129
Line -1 false 249 129 254 110
Line -1 false 253 108 248 97
Line -1 false 249 95 235 82
Line -1 false 235 82 144 100

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

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

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

egg
false
0
Circle -7500403 true true 96 76 108
Circle -7500403 true true 72 104 156
Polygon -7500403 true true 221 149 195 101 106 99 80 148

link
true
0
Line -7500403 true 150 0 150 300

link direction
true
0
Line -7500403 true 150 150 30 225
Line -7500403 true 150 150 270 225

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
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
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
