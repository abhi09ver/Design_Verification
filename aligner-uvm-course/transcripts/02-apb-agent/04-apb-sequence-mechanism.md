# APB sequence mechanism

*Chapter: APB agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to implement together the EP sequence mechanism.
We will implement the driver and the sequencer.
Then we will create instance of those two classes in our APB agent.
And finally we will create those three sequences that we talked about in the previous tutorial.
The simple sequence read, write and random and use them in our register access test.
Our starting point is the APB Sequence Mechanism Practice project, which we must copy in our working area and make sure that you unselect this option under Tools and Simulator.
Show output file after run.
The first thing that we must do is to, um, create the file for the APB sequencer.
So let's do this.
We said that our sequencer must inherit from UVM sequencer.
So let's create a class like this.
And now we must add the mandatory code for each UVM component class that we declare the UVM component utils, macros, and the new constructor.
And that's it for our sequencer.
Let's click save.
Now let's include the file in the app package.
And let's see if the code compiles.
Everything looks good.
We created the sequencer.
And now let's create the driver class.
First let's create the file.
Now let's create the class.
Again, the driver class must inherit from UVM driver.
So let's do this.
Let's add the mandatory code for the UVM component.
Pay attention to the copy paste problem.
And now in the run phase of the driver, we must get that next item and just print a message instead of driving it on the bus.
And then call item done.
So this is the item in which we get the information sent from the sequences.
And now let's call Getnext item and use this as an argument in order for the Getnext item task to put the information in here.
Now when a sequence will be called and it will drive one item, we will get that information through this pointer here.
Let's just print a message with this information.
And finally let's call item done.
In the next tutorials we will implement the logic for driving the item on the bus.
But currently we just print some message here to see that the sequence mechanism is working.
Let's include the file in the APB package and let's see if everything compiles correctly.
We have a problem, let's fix it.
I put here the wrong argument.
It should be the item drive.
Let's fix this.
Click save and run again.
Everything looks okay.
Let's move to the next phase in which we create those two instances.
One common configuration field in all the agents is to determine if the agent is active or passive.
The difference between an active agent and a passive agent is that the active agent has this driver and sequencer instantiated, and usually this is controlled via a field called active passive in the agent config.
So let's create that field.
We use as the type of this field this UVM active passive enum which is already declared under the UVM library.
And this can have two values UVM active or.
UVM passive.
Let's make our agent a default to be active.
And let's create a getter and setter for this field.
That's the getter.
And now let's create the setter.
See if everything compiles.
We did some mistake here.
I just misspelled void.
Save and rerun.
Everything looks good.
Now let's create the instances of the driver and the sequencer in our APB agent.
But we will do this based on the active passive field from the Agent Configuration class.
First, let's create the handlers.
In the build phase.
Let's create the instances.
So only if the agent is configured as being active we create those two instances.
And finally in connect phase we must connect that sequence item port and sequence item export.
So let's do this.
And that's it.
Let's save and see if everything compiles.
Everything looks good.
Now let's move to our final step in which we create the sequences.
First, we will create this sequence base in which we declare the sequencer.
And then from this class we will create those three sequences simple read and write and random.
So let's do this first.
The sequence base.
We must add the mandatory code for a new VM object because a sequence is an UVM object.
That's it.
And now let's create that sequencer using the UVM declare sequencer macro.
That's it.
Let's save.
And let's include this file.
We must include it after the sequencer because we used this class in here.
So the compiler must know about UVM sequencer when it will parse this file.
We made a mistake.
Let's fix it.
The problem is actually from here.
Let's save and try again.
Everything looks good.
Now let's create the simple sequence.
And this one must extend from our base class.
Let's add the mandatory code for an UVM object.
Okay, now let's create a random item which we will send to the sequencer.
Because this one is a class, we must create it before the randomization.
So let's do this in the constructor.
We could also use for this the pre generate function.
But the constructor is also a good place for this.
And in the body let's call that start item and finish item.
That's it.
Let's include the file and see if everything compiles.
We made a mistake.
Let's fix it.
This one should have been a string.
Let's try again.
Everything looks good.
Now let's go to our test and try to call this sequence to start this sequence.
So what we can do is go here and create an instance of this sequence and send it to the sequencer.
And actually the name here should have been simple.
That's another mistake.
But let's quickly fix it.
Save.
And let's go to our test created here.
Let's randomize the sequence.
And let's say that we want to constrain the address to value two two, two.
And finally we must start the sequence.
And we must pass here the sequencer.
Okay.
And now let's see if we, um, see this information, uh, reaching the driver.
Let's give it a try.
Okay.
If we look in the printed messages, we can see that the driver said it is driving this information direction.
Read and address two, two, two.
So our sequence was passed.
Our item was passed correctly down to the driver.
Now what we can do is to go to the sequence and try to replace this code with that UVM do macro to see if everything works correctly.
So let's give it a try.
Let's comment out this code and now we use that UVM do macro.
Let's click save and see if everything goes correctly.
And let's look at the printed message.
And we can see now that the address is no longer what we wanted to drive that two, two, two from our test here.
And the problem is that the UVM do macro will regenerate our item again.
And whatever we constrained from above no longer matters.
And we can fix this by using the UVM send macro instead of UVM.
Do so.
The send will not create and generate that item.
It will only call that start item and finish item.
So let's give it a try and see if our value for the address 2 to 2 will reach the driver.
So you see, now everything looks okay.
We passed that 2 to 2 value all the way down to the driver.
So you must pay attention when you have to use the UVM two or UVM send.
So the thing is that UVM two will randomize that information, um, that you want to send and UVM send will only send that information to the driver.
And in this case, because we already have a random item here which is generated when we randomize this sequence and we apply that constraint, we no longer need this UVM two.
We only need UVM send.
Now let's create that read write sequence.
Again, it will extend from our base class.
We must add the mandatory code for an UVM object, which is this one.
Pay attention to the argument of UVM object utils.
And now let's also include this one in the app package.
And we said that our read write sequence will have as an API a random address.
And a random write data to use when the right part will be done.
Now let's create in the body task um, an item first for the to read that address and then to write to that particular address.
So let's do this.
Let's create the item.
Now let's randomize it and constrain the direction and the address.
Direction to be the read.
First we do the read and then we want the address to be whatever we passed here.
So we put this one here.
And then we want to call start item and finish item.
And we pass the item and finish item.
And again we pass the item.
Now let's call this sequence also in the test.
Let's do another begin.
Let's also copy paste this code to randomize it.
But pay attention to the copy paste problem.
And now let's constrain the address to be address four.
Let's give it a try to see if our sequence will do a read with address four.
We made some mistake.
Let's fix it.
Is not the item here, it's simply the address again a copy paste problem.
Pay attention to this type of issues.
Now if we look at the printed messages we can see that this is the second read from this.
So the first one is from the simple sequence with address 2 to 2, but the second one is the read part from the read write sequence, but the address is four kb2.
The problem is that we wanted to drive this four value here, and the issue is in the read write sequence, where we constrain the address of the item to be equal to the address from this sequence, from the read write.
Actually, this constraint means that we want the address in the item to be equal to the address in the item.
And this is a very common problem and very difficult to debug.
The solution here is to force the simulator to understand that we want the address from the sequence, and we can do this using the keyword local like so.
Let's click save and let's see if our second axis is a read axis from address four.
Let's see if it worked.
And the second axis is a read axis from address four.
So this one worked.
Let's go back to our sequence.
And let's try to replace this code with the UVM two macro.
We must use the UVM do with macro because we also want to apply some constraints.
So let's do this.
And first argument is the item that we want to send to the sequencer.
And then are the constraints.
And we simply copy these constraints here.
And we can get rid of this code.
And we can even get rid of this create part which creates this item because the UVM do macro will also create the item for us.
So let's see if this one works.
It did.
We have the second axis added from address four.
Now let's do the same thing for the right.
And you can see that using this UVM do macro makes the code easier to write.
And here we can simply put here the direction to be right.
And we also want to constrain the data to be equal to the right data that we want to drive.
And we can see that we have two accesses to address for first read and then a write with this random data which we can also constrain if we want.
Now let's implement the last sequence which is that random sequence.
Let's add the mandatory code.
And we said that we want this random sequence to have in its AP a field called num items number of items, which is a random unsigned integer.
And let's apply some constraint to this one to generate some smaller values.
Because this is an unsigned and we don't really want to send a huge amount of items.
And let's say that we want a random number of items between 1 and 10 in the body part.
We want to send simple sequence this many times.
So let's create a for loop.
And let's create this simple sequence instance here.
Let's randomize it.
And let's start it.
And when we start the sequence we must specify the sequencer.
And we can use here either m sequencer or p sequencer.
It doesn't matter.
And we specify its parent this.
Let's include this one in our package.
Let's go to our test again.
Let's do a begin end.
Create an instance of this sequence.
Let's randomize it.
And let's say that we want to send only three random items.
And let's start this sequence.
And let's see if we have three random items after our read and write accesses.
And after our read and write we have these three items here.
Now let's go to our random sequence and see how we can apply that UVM do macro.
And we simply pass this sequence and we can get rid of this code and even the create part.
So it looks much cleaner.
Let's give it a try.
And we can see these three random accesses after our read write sequence, but it's a bit difficult to see which sequence was sending this item.
But we can fix this by going to the driver and change a little bit the message.
What we can do here is add the full path of our item.
And now when we run, we will be able to see which sequence was driving that particular item.
So you can see from our messages that first the simple sequence drove this item.
Then the read write sequence drove this one, and then the random sequence sent to the driver.
These three random items.
What we can finally do in our test.
It's make this a little bit more random and we can do all these.
Um, three sequences in parallel simply by, um, wrapping them up in a fork and then a join.
Let's run again.
So remember, now that the simple sequence, the read write sequence, and the random are running in parallel.
So first the simple sequence wins the sequencer and sends this item.
Then the read write send the read part of the item.
Then comes the random part with its first item.
Finally, the read write can send its write part of the item, and also at the end, the random sequence sends the last two items that it wants to drive.
That's it for this tutorial.
Thanks for watching and see you in the next tutorial.
Bye!
