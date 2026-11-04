# MD protocol checks we already discussed about

*Chapter: MD agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to talk about the MD protocol checks we already discussed about.
What are protocol checks when we develop the app agent.
But just to reiterate, the protocol checks are rules describing the correct behavior of the signals.
And these rules should be extracted from the protocol specifications document if exists.
And in our case for the MD protocol, this if exists is very important because we don't have a documentation for the MD protocol.
So this means that we have to extract the rules of the protocol from the aligner specifications.
And this is quite a difficult task because we need to identify the rules which are independent of any Dot implementation.
But for MD protocol, we already did this when we had the tutorial about the MD protocol.
And we extracted from the documentation these 12 rules.
And if you remember, for example, we extracted these two rules regarding the data width from these two statements from the spec and also for the valid.
We extracted this rule from this part of the spec, and we did the same for all those 12 rules.
So there is no need to go once again through the aligner specifications.
But besides these 12 rules which were clearly stated in the aligner documentation, we can also add four more rules which are not specified there.
But they make sense.
And when you are in this situation in a real project, you should double check with the designer and the system architect to make sure that the rules you think should apply to the protocol are also valid from their point of view.
But let's look a little bit at these four extra rules.
The first one is this one valid?
Cannot have an unknown value.
And it makes sense because based on the valid signal, we determine if there is an MD transaction ongoing or not.
So we need valid to be all the time, either 0 or 1.
So it cannot have values like x or z.
The next extra rule is regarding the ready signal.
Red is valid while valid is high, and it's in the same line as the rules for offset and size and data, it makes sense to have a ready either 0 or 1, while valid, is high because when valid is low, ready does not matter.
The third rule that we introduce is this one offset plus size cannot be bigger than the data width in bytes.
And again this is a rule that we previously discussed.
It makes sense because with this rule you cannot go outside the data bus physical width.
So it does not make sense to send let's say four bytes with size four from offset three, because there is no physical bits on the data base on which to put that information.
And finally, the last rule is similar to one that we had on the APB.
MD transfer cannot have an infinite length, and we will use this rule just to make sure that our MD interface does not get stuck, just like we did for the APB.
The majority of the rules will be implemented as assertions in the interface, and once again, it is better to implement those rules as assertions, even though they are harder to write and harder to debug, because in this way you can reuse that interface when you are doing formal verification.
And remember that formal verification relies heavily on assertions, and if you can, write them once and use them in different ways of verifying a duty like simulation based or formal, then that's all for the better.
The last rule regarding the length of the MD transfer.
Just like for the APB, we will implement it as a check in the monitor.
So all these will be quite similar to what we did on the APB.
And this is a good opportunity for us to try to get a little bit more practice with writing assertions.
However, the first rules regarding the data width will be implemented as special checks, which will be executed when the interfaces get instantiated.
So this will not be assertions because, for example, we don't want to check the data width on every positive edge of the cloak because we know that the data width is static.
So we want a check to be triggered right away when the interface gets instantiated.
Because if the data width is not correct, then everything else falls apart.
So for example, if we instantiate the interface with the data width equal to three, then it makes no sense because with the MD protocol, we cannot send a byte using a database of width three.
And in the next tutorial when we implement all these checks, we will also try to run especially these two checks on all three major simulators from cadence, Synopsys and Mentor, and we will see how our code behaves on these three different simulators.
And just to get a perspective on where these checks will stay and what they will verify.
So we will implement the checks in the monitor of the MD agent and also in the interface.
And because we instantiate two of these agents, one for the ADCs interface and one for the ticks interface, our checks will verify in the same time both of these interfaces.
That's it.
For this tutorial we discussed again about what are protocol checks, how to identify them.
And especially we discussed about what MD protocol checks we will implement in the next tutorial.
We will implement these checks together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
