# VGDC: The Card Game

## Design Spring 2026 Mega Collab GDD

## Premise

A physical, multiplayer card game where players will face head-to-head to destroy the other’s Deck, forcing them to draw to their doom.

## Inspiration & Goals

* We’ll be taking inspiration from popular physical and online card games  
  * Magic the Gathering (Commander Format)  
  * One Piece: The Card Game  
  * Hearthstone  
  * Legends of Runeterra  
  * Riftbound  
* Light, fun, and goofy card game  
* Completable within this quarter’s workshops  
* Learn about creating a card game\!

## Game Loop

### Game Setup

* Each player starts with a **20 Card Deck** with a **Maximum of 2 Duplicates** per Unique Card that can hold any proportion of **Minions, Spells, and Traps**  
  * Cards are played using **Tickets**  
* Each player also has **1 Leader** (separate from the deck size) that decides the “color” of the deck  
  * (Tokens / Cards relevant to other cards’ effects do not factor into this deck limit)  
  * Leaders can be played using **Tickets** or **Discarding Cards from their Deck** (for example, a Leader may cost **two Tickets** or be played by **Discarding 2 Cards from your deck**)  
  * When a Leader is killed, the Leader is sent to the **Discard Pile**

### Game Start

* Each player immediately draws their Leader into their hand  
* Each player draws the **first five cards** of their deck and **discards two cards** from this draw of 5  
* Determine which player goes **first**

### First Turn

* The player who goes first gets **one Ticket** which start **untapped**  
* This player **draws a card**  
* This player may play any card with satisfying cost during their turn, **tapping Tickets as used** or **discarding cards as necessary**  
* This player may choose to end their turn when they believe they are done

### Second Turn

* The player who goes second gets **two Tickets** which start **untapped**  
* This player **draws a card**  
* This player may play any card with satisfying cost during their turn, **tapping Tickets as used** or **discarding cards as necessary**  
* If any **Traps** are activated during this player’s turn, they will be resolved **immediately**  
* This player may choose to end their turn when they believe they are done

### All Other Turns

* Start of Turn  
  * The player gets **two more Tickets** up to a **Maximum of 10 Tickets**  
  * The player **draws a card**  
  * All **previously tapped cards** become **untapped**  
* In-Turn  
  * The player may play any cards with satisfying cost during their turn, **tapping Tickets as used** or **discarding cards as necessary**  
  * The player may choose to **Attack** any played card on their opponent’s board (unless otherwise stated) with an **untapped Minion card**, **tapping the card**  
  * The player may choose to **Attack** the opponent’s Deck (unless otherwise stated)  with an **untapped Minion card**, **tapping the card** and forcing the opponent to **discard as many cards from their deck as damage taken**  
  * If any **Traps** are activated during this player’s turn, they will be resolved **immediately**  
  * This player may choose to end their turn when they believe they are done

## Constant Game Rules

* A player may only have at **Maximum 10 Tickets**  
* If at the end of their turn the current player has **more than five cards in their hand**, the current player chooses which cards to **discard down to the five card hand limit**  
* If a player runs out of cards in their deck, they **Reshuffle their Discard Pile into their Deck** and lose **one from their Maximum Reshuffles**  
  * (The **Discard Pile** is **shuffled** and does not immediately become the player’s deck)  
* **Minions**, when played, start **tapped** (unless otherwise stated)  
* **Traps** are **discarded** after reveal and activation (unless otherwise stated)  
* When cards are discarded, they are discarded **face up**  
* Players can **Reshuffle their Discard Pile into their Deck four times**  
  * If a Player runs out of **Reshuffles**, **they lose**\!

### Combat Rules

* When engaging in an **Attack**, Minions/Leaders (Units) will strike each other in combat simultaneously  
* Each Unit has a **Damage** stat and a **Health** stat  
* **Damage** deals “damage” to the **Health** of the opponent ***or*** if applied to the opponent’s Deck, forces them to discard as many cards as the damage they took  
  * For example, a 3 Damage, 2 Health (“3/2”) Minion attacking a 1/3 Leader results in the Minion taking 1 Damage (ending with 3/1 stats after the combat) and the Leader dying  
  * If a player takes 5 damage to their Deck, they must discard 5 cards from their deck  
* When a Unit **dies** it is sent to the Discard pile (unless otherwise stated)  
* If Traps are relevant to a combat, they will activate **depending on their stated conditions** (defaulting to before combat starts)  
* If a Unit has an ability, apply it as stated  
* After a turn has ended, all damaged Units heal to full health  
  * In the example stated above, the 3/2 Minion that took 1 Damage (becoming 3/1) returns to its base stats of 3/2 after the turn ends. This means that if it were to engage in combat or be attacked again on future players’ turns, it would have a stat line of 3/2

### Generic Stat Budgets

* The rough stat budgets for different cost Units if they have **no abilities**  
  * 1 Cost \- 3 (= 1/2, 2/1, 0/3, etc.)  
  * 2 Cost \- 5  
  * 3 Cost \- 7  
  * 4 Cost \- 9  
  * 5 Cost \- 11  
  * 6 Cost \- 13  
  * 7 Cost \- 15  
  * 8 Cost \- 17  
  * 9 Cost \- 19  
  * 10 Cost \- 21 (= 11/10, 5/16, 20/1, etc.)  
    * A Unit’s ability can nerf or buff this statline

