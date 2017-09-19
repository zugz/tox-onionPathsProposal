# The problem
The aim of the onion is to allow peers to send messages addressed by Tox ID, 
while ensuring that no party can link together any two of the following items 
of information about any peer:

* its IP address;
* its long-term public key;
* the IP addresses or long-term public keys of its friends, or of the friends 
  of its friends, etc.

We address in this document the problem of constructing onion paths in a way 
which isn't vulnerable to attacks which allow such links to be made.

Denial of service attacks are a separate problem not addressed here.

# Background
## The onion
We use the onion for two primary purposes: to _announce_ ourself and to 
_search_ for friends. This involves finding and then regularly sending onion 
requests to peers whose DHT public keys are close to the corresponding 
long-term public key - our own when announcing, or that of the target friend 
when searching. We refer to this long-term public key as the _target_ of the 
request. We refer to the area of DHT space around our long-term public key as 
our _announce neighbourhood_, and the areas around the long-term public keys 
of our friends as _search neighbourhoods_.

The basic mechanism of the onion is to route each request via an _onion path_ 
consisting of three peers. We will term the three layers of an onion path as 
the _entry_ layer, the _medial_ layer, and the _exit_ layer. So when we make a 
request, we choose a entry node, a medial node, and an exit node, then we send 
a packet to the entry node, who forwards it to the medial node, who forwards 
it to the exit node, who sends it to the destination of the request. Any reply 
then comes back along the same path. The only information a node in the path 
learns is which of the three layers it occupies and the IPPorts of the two 
peers it directly communicates with.

## Attack techniques
When a tox node joins the network, it creates a DHT keypair, and the public 
key becomes its location in the DHT. Creating a keypair is a rather cheap 
cryptographic operation (I measured it taking 0.0007s on my machine), so it is 
easy to position yourself where you please on the DHT by creating keypairs 
until you hit upon a suitable public key. So we assume that it takes 
negligible time and resources to create a keypair which is closer to a given 
position than any existing node on the network (how realistic this actually is 
depends on the size of the network and the computational resources of the 
attacker).

So an attacker can set up nodes to listen at certain positions in the DHT.
Even more perniciously, it can create new nodes in response to requests - if a 
victim asks the attacker for nodes close to a given key, the attacker can 
create some new nodes close to that key and then respond to the request with 
their details.

We can assume that the mapping between IPPorts and DHT public keys is known to 
an attacker, since crawling the DHT network is enough to determine it. So if 
an attacker observes our request as it is sent from the exit node to its 
destination, the attacker learns the approximate long-term public key 
targetted by the request. This approximate knowledge can easily be upgraded to 
precise knowledge, by starting nodes in the neighbourhood our requests are 
being made to such that we end up sending requests to the attacker's nodes. 
Announce requests can be distinguished from search requests based on the rate 
at which the requests recur. So, we assume that an attacker observing the 
traffic between the exit node and the destination learns all information about 
a request except its source.

An attacker who can observe the communication between the sender of a request 
and the entry node and between the exit node and the destination can link the 
two observations by the timings of the packets, and so link the sender's IP 
address to the target long-term public key of the request. If the attacker 
actually controls the entry node or the network connection between us and it, 
they can confirm the link by delaying packets.

If we use the same exit node for requests of different types in a way that 
allows the exit node to determine that the requests come from the same source, 
for example if we use the same medial node, then an attacker controlling the 
exit node will be able to link the corresponding information - if one request 
is an announcement while the other is a search, they can link our long-term 
public key to that of our friend; while if the requests are searching for 
different friends, the attacker can determine that those long-term public keys 
have a common friend.

## Current implementation
At the time of writing, toxcore creates paths as follows. We maintain a pool 
of nodes to use when building paths. In an initial bootstrap phase this 
consists of DHT bootstrap nodes. After that, it is populated from two sources: 
from the DHT and from the onion. We maintain a pair of "DHT fake friends", 
meaning that we query the DHT for nodes close to a pair of randomly chosen 
positions, and add the nodes we find to the pool. Meanwhile, we also add to 
the pool any node which replies to an onion request. To create an onion path, 
we randomly choose three nodes from the pool.

This system is vulnerable to attack. In particular, if an attacker controls 
many nodes in our announce neighbourhood, they will respond to our announce 
requests and so end up in our onion path pool, and so we are likely to create 
a path for an announce request to one of the attacker's nodes using an entry 
node which is controlled by the attacker. Hence the attacker links our IP 
address to our long-term public key. We are also likely to use entry and exit 
nodes controlled by the attacker for our friend searches, so the attacker can 
also determine the long-term public keys of our friends.

If we do not use the DHT, we are protected from this particular attack since 
we use only TCP relays as entry nodes. But an attacker filling our announce 
neighbourhood with their nodes can observe them being used as exit nodes for 
our friend search requests, and so link our long-term public key to those of 
our friends; the link can be confirmed by observing our choice of medial 
nodes.

# Proposed system
## Overview
We keep the exit nodes we use for announcements independent from those we use 
for friend searches, and moreover keep those we use for each friend 
independent from those used for other friends. We keep all exit nodes 
independent from entry nodes, and we also keep entry nodes used for 
announcements independent from those used for friend searches.

For each of these classes of node, we maintain a _pool_ of nodes which we use 
for the corresponding purpose. Initially, we fill the pools by using onion 
requests to find some random nodes in the DHT network at graph distance 2 from 
bootstrap nodes; explicitly, to fill a pool, we ask a bootstrap node for nodes 
they know close to a randomly generated key, then ask each of the nodes 
returned for nodes they know close to a fresh randomly generated key, and add 
the nodes they give us to the pool. We try to avoid using the same bootstrap 
node to fill multiple pools.

When paths fail, we try to remove nodes from our pools only when we are fairly 
sure that the node is really no longer working, and to avoid some attacks we 
check this by using nodes from independent pools. When we do need to refill a 
pool due to too many nodes going down, we use onion requests to ask nodes 
still in the pool for nodes they know close to a random key and add them.

## Details
We maintain a number of pools of nodes: an _announce entry pool_, a _friend 
entry pool_, an _announce relay pool_, and one _friend relay pool_ for each 
offline friend.

A _valid_ onion path consists of an entry node from an entry pool and distinct 
medial and exit nodes both from a single relay pool, with the entry and relay 
pools being of the same type, i.e. both announce pools or both friend pools. 

When sending an announce request we use a valid path constructed from the 
announce pools, and when sending search requests for a friend or sending 
data-to-route packets to a friend, we use a valid path constructed from the 
friend entry pool and the friend relay pool corresponding to the friend.

Each pool can contain at most 6 nodes.

If a path times out, we add a blackmark to each of its nodes. We avoid where 
possible constructing paths in which more than one node is blackmarked. If we 
construct a path with an exit or medial node which has two blackmarks, we swap 
the entry node for one from the other entry pool. When we construct a path 
with unblackmarked exit and medial nodes, we check to see if there is a doubly 
blackmarked node in the other entry pool, and if so swap it in as the entry 
node. A node with three blackmarks is considered _bad_, and is not used in any 
path. If a request receives a reply, all nodes in the path have all blackmarks 
removed. Nodes freshly added to a pool start with one blackmark.

If there are no non-bad nodes in a pool, we add a random bootstrap node to the 
pool (replacing a random bad node if necessary). Where possible, we avoid 
picking a bootstrap node which has previously been added to any pool, or which 
we are connected to as a TCP relay.

While the number of non-bad nodes in a pool is less than 4, once per 15 
seconds we perform a _branching random walk_ in the DHT network to fill the 
pool. The origin of the walk is a random non-bad node in the pool to be 
refreshed. The length of the walk is 2 if the origin node is a bootstrap node, 
and 1 otherwise. To perform a walk, we use a valid onion path to send a 
request to the origin of the walk searching for a freshly randomly generated 
key. If we get a reply and the walk was of length 0, and if the replying node 
is currently not in any pool, we add it to the pool if we can do so without 
overfilling the pool, replacing a bad node if necessary. If we get a reply and 
the walk was of length n+1 and the pool is not yet filled with non-bad nodes, 
for each of the nodes given in the reply, we start a walk of length n with 
that node as the origin. 

When we are not connected to the DHT, instead of the above rules we consider 
the entry pools to consist of TCP relays we are connected to, divided between 
the two entry pools, aiming for an equal number in each with a preference for 
the announce entry pool. We do not use the blackmark system for TCP relays, 
relying instead on the usual timeouts for TCP relays. Optional recommendation: 
increase the default number of TCP relays to connect to and reserve for onion 
use from 3 to 4, so we can have 2 in each pool.

When beginning a search to fill an announce/friend close list, we use a node 
from the corresponding relay pool as the destination.

In the DHT module, we change the eviction policy for all but the closest 
k-buckets in our close list: if a bucket is such that the closer buckets 
contain at least 16 nodes between them, then we remove a node from the bucket 
only if it is timed out.

## Justifications
To minimise the chances of a successful attack, we aim to keep the pools 
_independent_, meaning that whatever an attacker does, the probabilities of 
them controlling nodes in our various pools are independent; i.e. an attacker 
has no way to increase their chances of controlling nodes in a given pair of 
our pools beyond $\epsilon^2$ where $\epsilon$ is the probability of 
controlling a node in a given single pool.

We avoid removing a node from a pool until we have tested it with independent 
nodes to foil attacks wherein entry nodes try to force us to cycle our exit 
nodes, or exit/destination nodes try to force us to cycle our entry nodes. The 
lack of symmetry between entry and exit nodes in the testing scheme is because 
we must use an exit node only for the purpose assigned to it.

We fill the pools via the onion rather than directly via the DHT, because we 
don't want exit nodes to know our IP address and we don't want an attacker to 
be able to target an attack on our IP address aimed at causing us to use the 
attacker's nodes as our entry nodes.

We use medial nodes for extra protection against attackers who might try to 
deanonymise us by tracing back through our paths from our announce/search 
neighbourhoods, by observing each node in turn.

We use walks of length 2 rather than 1 when starting from a bootstrap node to 
prevent excessive strain on the nodes in the close lists of the bootstrap 
nodes. There is no serious security advantage, as an attacker can point us to 
their own nodes when replying to a request in a walk. We use a random walk 
rather than a "fake friend" approach in which we search recursively for a 
single target key and select those nodes we hear about closest to the target 
key, because with the fake friend approach a single attacker encountered 
during the search can ensure they control the nodes we select, by starting up 
new nodes with keys generated close to our target key and pointing us to them.

We must change the way nodes are added to the close list in the DHT module, 
because currently it is easy for an attacker to take over the entire close 
list of a chosen node by generating appropriate DHT public keys, and so ensure 
that the bootstrap nodes refer searchers to the attacker. However it is still 
important that the closest nodes to us are in our close list, so we must 
continue to replace even good nodes with closer nodes in the closest few 
non-empty buckets.

An attacker controlling the bootstrap node we ask when first filling a pool 
can quite easily ensure we fill the pool with their nodes, by directing us 
along our random walk exclusively to their nodes. This is why we avoid using 
the same bootstrap node for two pools. Note however that an attacker 
controlling multiple bootstrap nodes has the opportunity to e.g. deanonymise 
those users unlucky enough to use the attacker's nodes to fill both their 
announce pools. As far as I can see, this is a problem with any possible 
scheme: bootstrap nodes are our only means of introduction to the network, and 
a bootstrap node can choose to introduce us exclusively to the part of the 
network it controls.


## Backwards compatability
No API or protocol changes are proposed, and nodes using the proposed scheme 
should play happily with nodes using the current system. The save format must 
change, however.
