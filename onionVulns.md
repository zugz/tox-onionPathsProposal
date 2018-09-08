# Known vulnerabilities in the tox onion

## 1: Announce nodes can read public keys from onion data packets
Source: https://github.com/TokTok/c-toxcore/issues/1121

Outline: The data public key stored on the announce node by the announcer can 
be replaced before sending it to a searcher with a key generated by the 
announce node; due to insufficient layers of encryption, the announce node 
will then see the public key of the searcher. By generating a suitable DHT 
public key, an attacker can position themselves to be an announce node for 
their target.

Consequence: an attacker who knows the long term public key of their target 
can, by a fairly straightforward and cheap directed attack, determine the long 
term public keys of the friends of the target when they search in the onion 
for the target.

## Choice of onion path nodes can be manipulated
Source: https://github.com/TokTok/c-toxcore/issues/596

### 2a: Announce nodes used as path nodes
Outline: If an attacker controls many nodes in (or even just near) our 
announce neighbourhood, they will respond to our announce requests and so end 
up in our onion path pool, and so we are likely to create a path for an 
announce request to one of the attacker's nodes using an entry node which is 
controlled by the attacker. We are also likely to use entry and exit nodes 
controlled by the attacker for our friend searches; if the attacker is able to 
determine the DHT key corresponding to the IP address of the destination of 
such a friend search (by crawling the DHT), they thereby obtain an estimate of 
the public key of our friend.

Consequences: an attacker who knows the long term public key of their target 
and is willing to devote some moderate network resources and time to the 
attack can determine the IP address used by the target to connect to the tox 
network, and with some substantial further effort may determine the public 
keys of the friends the target tries to connect to.

### 2b: Sybil attacks and DHT poisoning
Outline: One way or another, onion path nodes chosen by a target have to come 
from the part of the tox network the target can see. By various techniques, an 
attacker can attempt to ensure that a large proportion of the view of the 
target consists of the attacker's nodes. The least subtle and most expensive 
such technique, which is unpreventable, is for the attacker to simply 
establish a number of nodes comparable to the size of the tox network.

Consequence: Whatever modifications might be made to the way onion path nodes 
are chosen from the network and to the details of the DHT implementation, a 
resourceful attacker can ensure they frequently control both the entrance and 
target node of a path, and hence determine the IP address of the user of the 
path and hence link IP addresses to public keys and determine friend relations 
as above.