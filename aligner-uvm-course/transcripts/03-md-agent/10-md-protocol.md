# MD protocol

*Chapter: MD agent · source: attached*

Hi, my name is Christiane Slav, and in this tutorial we are going to talk about the MD protocol.
MD stands for Memory Data.
This is a made up protocol.
This is not a standard protocol that you can find online.
So the only documentation for this protocol can be found in the aligner specifications.
To understand better this protocol we need to see where it is used in our aligner RTL.
The MD protocol is used on the edicts and tags interfaces to get into the aligner.
The unaligned data from the ethics side and to send the aligned data on the take side.
The MD protocol has on its signals a data bus, which in our case is 32 bits in width.
This means four bytes, and we can visualize this four bytes as lines numbered from 0 to 3.
So for example, byte zero reads represented by bits seven down to zero from the data bus, byte one represents bits 15 down to eight, and so on.
In this MD protocol, we can specify which bytes out of these four are valid, and we can do this via two other signals size and offset.
Offset represents where the valid byte starts from.
So for example offset zero is from here and size represents the number of valid bytes starting from the offset value.
So for example, this size one and offset zero means that this first byte is the only one which is valid size one and offset one.
It's this one.
So because offset it's equal to one, it means that the only byte valid due to the size equals to one starts from here, and it is the same for offset two and offset three.
We can also send in this MD protocol two bytes at a time, and in this case size will be two.
So you can see size two.
And offset zero means that these two bytes are valid and the same for size two and offset two.
The other combinations of size two and offset are considered illegal, but only by the aligner, not from the protocol point of view.
And for size four, we have this only combination here with size four and offset zero.
The other combinations of size and offset are considered illegal, but they are considered illegal only by the RTL, not from the protocol point of view.
So from the protocol point of view we can send any combination of size and offset.
So, for example, we can still send size three and offset zero like this.
But RTL will consider this illegal.
It will drop this and it will increment the drop counter.
For this.
And in the aligner specification, there is a formula telling us what combinations of size and offset are legal or not.
So from the aligner point of view, these are all the legal packets that we can send and they will be accepted.
So we have these four combinations for size one, these two combinations for size two, and only one combination of size and offset for size for the aligner has this control register which defines these two fields offset and size.
And these two fields control how we want the data to be aligned.
So for example, if we have this offset equal to two and size two, it means that we want to align the data on these two lanes here on byte two and three.
And let's see a short animation to understand what this means, how the liner will align the data.
So you see, regardless of how the data is received, the liner will align it on these two bytes here.
So these were the packets as received on the air interface as unaligned data.
And this is how the aligner will output this data aligned.
In the next tutorials we will learn how to build agents for this add and take interface.
So we will build this add agent which will send that unaligned data.
And we will also build this takes agent which will get from the RTL that align data.
And of course because both of them will be connected to signals based on the MD protocol, there will be a significant part of these two agents, which will be common, but it will be common from the class definition point of view.
Um, we will have two different instances of this MD agent, one for the aortic side and one for the dark side.
Now let's jump to the aligner data sheet and try to identify the signals part of the MD protocol.
And if we jump to the interface section, we can see here in this table that we have several signals for the MD 86 side.
So these are the signals part of the ADCs interface.
And below are the signals for the ticks interface.
And we can see that we have for both of these interfaces valid data that offset and size with which we can control which bytes of the data are valid.
And then as a response for from the slave we have ready and error.
So for the ADC side our agent will be master agent.
So this means that it will drive valid data offset and size.
And the RTL will be the slave, so it will drive a radian error.
But on the takes part, the RTL is the one which is the master.
So the RTL will drive this valid data offset and size and our tax agent will drive ready and error.
So just to make it clearer in this picture, the Asterix agent will be master on that MD Eric's signals group of signals and the RTL will be the slave.
And on the group of signals named with MD takes, the RTL will be the master and our tax agent will be the slave.
And let's list all the signals which will be part of the interface connected to this ADC site on one side, and this takes interface on the other side.
So we will have the group of signals driven by the master towards the slave.
And this will be valid data offset and size, and the signals driven by the slave towards the master will be ready and error.
And of course we need to have clock and reset.
One other important thing to mention here is the width of these signals.
So for example we have this data width which represents the width of this data signal in bits.
And then for offset and size we have some formula to determine the width of these signals.
But you can notice that the formula is based on the data width.
So in our case we will use this data width with value 32.
And in this case offset will actually be two and size three.
But now that we identified the signals part of this MD protocol, let's try to identify the rules which govern these signals.
And for this we need to jump to the aligner data sheet because that is the only source for us from which we can extract these rules.
The first rule that we can determine is related to the data width in the aligner documentation.
The data width is actually a parameter of the RTL called aligner data width.
And we have two rules for this one.
The value must be a power of two, and the minimum legal value of this parameter is eight.
So we can have values like eight, 16, 32 and so on.
So we have these first two rules.
Data width must be a power of two and data width minimum legal value is eight.
Now if we look at the valid signal we can see here that it states.
Once it becomes high it must stay high until ready signal is high.
So this will be the rule which will govern our valid signal.
And in the end we will make this rule an assertion in the interface.
So let's also put this rule in our table.
So the third rule once valid becomes high it must stay high until ready becomes high.
For the data signal.
We have this statement here.
It is valid while valid is high.
And it must remain constant until ready becomes high.
So we will have these two rules for the data.
Data is valid while valid is high and data must remain constant until ready becomes high.
And let's scroll now to offset.
And for offset we have similar rules.
It is valid.
While valid is high, it must remain constant until ready becomes high.
And here we get this statement.
Not all combinations of offset and size are legal, and we get here the formula to determine what combinations of offset and size are legal, but this is relevant only from the aligner point of view.
In our agent, we must still be able to drive illegal combinations in order to be able to test if the RTL really rejects those illegal combinations.
So let's put here the rules for the offset.
Offset is valid while valid is high, and offset must remain constant until ready becomes high.
Now for size we have similar rules.
It is valid while valid is high and it must remain constant until ready becomes high.
But we have this third rule value zero is illegal and must never be used.
So this will be part of our MD protocol because it makes no sense to drive a transfer on this MD protocol with size zero, saying that no byte is legal.
So let's put these rules in our table.
So we have these three sizes valid.
While valid is high.
Size must remain constant until ready becomes high and size cannot have value zero.
And finally we have for the ready we have no rule and for the error it says that it is valid only when both valid and ready are high, and it can be high only when valid and ready are high.
So let's put these, uh, two rules here for the error.
And with these 12 rules, we can actually build the entire MD protocol.
And if we go to this data alignment chapter and scroll down, we can actually see an image of the signals and how they toggle.
So remember that for um, all these signals uh data offset and size, we had that rule that they are valid while valid is high.
So while the transfer starts.
So they are valid from here up to here and they must remain constant until ready becomes high.
So until the end of the transfer.
So our transfer will start here and it will end here.
And of course it makes sense to keep all these information passed from the master to the slave constant until the slave can receive that information, and the slave responds with ready and error.
And of course, the error can only be valid while red is high and valid is high.
So here is another representation of how the signals should look like.
And we can actually determine that we have three types of transfers.
One is this one.
And it is without wait states.
So it will be the fastest access that we can have when valid becomes high ready.
It's already high.
So the access will start and end in the same clock cycle. then we can have an access with wait states and it has wait states, because the slave will take some clock cycles to respond with ready.
So the access will start here and the master will have to keep valid constant and data and offset and size until it receives from the slave the ready information telling it that the slave was able to get this information.
And finally we have an access with error in which the slave responds with error for this access.
And in this particular case, our slave will respond with error because we have this illegal combination of offset and size.
So extracting the rules of a protocol out of the documentation of an RTL that you have to verify.
It's a very common practice in real life.
So not all the time your duty will have this standard interfaces for which you can find documentation online.
There will be a lot of scenarios like this one, in which you have to go through the documentation of the dot and try to extract these rules, but usually you will have to follow all the time the same recipe.
First, you have to identify the signals part of that protocol, and then you have to identify the rules which govern that protocol.
So that's it.
For this tutorial, we discussed about where the MD protocol is used in our aligner RTL.
We identified the signals part of this MD protocol.
So this will allow us to build an agent which we can reuse, for example, in our case two times on the air intake side.
And finally we extracted the rules which must be applied to our MD protocol signals.
That's it for this tutorial.
Thanks for watching and see you in the next tutorial.
Bye!
