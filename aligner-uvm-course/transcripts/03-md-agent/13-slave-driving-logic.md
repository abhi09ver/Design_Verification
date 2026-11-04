# Slave driving logic

*Chapter: MD agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to code together the slave driving logic.
So we are going to implement the item drive slave.
Then the slave driver in the sequencer.
We are going to reformat the sequencer class and the master branch.
And then for the slave branch we are going to implement this base slave with this API.
And we will also implement the sequencer slave.
And finally we will implement the three slave sequences.
And we will also do the updates to the inheritance tree of the sequence classes.
So let's get started.
The starting point is the slave driving Logic practice project which we need to copy.
Let's resize the windows and let's unselect this open EP wave after run, because we only want to see the log in the beginning and make sure you have show output file after run unselected.
First, let's create the item drive slave class.
Let's include this file before we declare all the fields.
That's it.
Now let's continue in the file.
And here we will declare all the fields, define constraints and also implement that convert to string function.
So let's do this.
That's it.
Let's see if the code compiles correctly.
Everything run okay.
We have no error.
And now we can move forward to the driver.
To implement the driver we will create this class driver slave which will inherit from Cfmd driver.
And in here we will only implement that drive transaction task.
So let's create the slave driver class.
Before we move forward, let's include this file.
That's it.
And in here, let's declare that virtual interface type because we need to take from the agent config the virtual interface.
So let's do this.
That's it.
Now let's implement the drive transaction task.
Let's add a check to make sure that this item is sent to the driver when the master already started to drive something on the bus.
So basically we will check here that valid is equal to one.
First we will drive this ready to low, just to make sure that we have time to drive our entire response.
Then we will wait for the number of clock cycles which we have in the length field.
And here we will drive our response.
That's it.
Let's see if our code compiles so far.
We have an error.
Let's fix it in here.
When I did the casting, I forgot to design.
Let's save and try again.
Everything looks good.
Now, one other thing that we need to do in the driver is to implement the handle reset function in order to reset these signals back to their default state.
So let's do this.
That's it.
And in most of the cases this will be sufficient.
But let's try to implement a field in the agent configuration class in which we declare here some configuration field for the reset value of red, and this is because we might want to start our driver with ready equal to one, just to mimic a connection of this ready signal to a five for full status.
So let's do this.
Let's go to our agent config slave class and declare here a field called ready at reset.
That's it.
We declared the getter and setter for this ready at reset.
And let's also initialize it to value one and back in the driver.
Let's use the getter to set the value of a ready when reset comes.
Now one thing to pay attention to here is that we tried to access this.
Get ready at reset via the agent configuration pointer, but this agent configuration pointer is not declared here is declared in the CFS MD driver.
And if we go there we can see that the pointer is of type CFS.
MD agent config.
But we declared the field in the cfs MD agent config slave.
This means that in here in the driver slave, we need to declare the correct type for the agent configuration class.
So let's do this.
Let's take the type of this agent config slave and go to our driver slave and declare it here.
And we actually can use the same name as the pointer declared in the driver here.
But when we are here in the driver, when we access below the agent config, we will access the type declared here, not the one from the parent class.
And this is called variable hiding in object oriented programming.
And the final thing is that we need to assign a value to this pointer.
Because this one is currently null.
And we can do this in the end of elaboration phase, because we know that at that point the agent config pointer from the driver, it's already allocated by the connect phase function from the agent.
So let's do this.
First let's make sure that the agent config pointer from the parent class is not null.
And now let's cast the pointer from the parent class to the one from here.
And let's make sure that the casting is successful.
That's it.
Now let's go to the agent slave class and make sure that we overwrite the correct type for our driver.
That's it.
And also, let's not forget that our CFS MD agent class has two parameters the data width and the type of the item drive.
That's it.
Let's save and see if our code compiles correctly.
We have an error.
Let's fix it.
Here I forgot to put this call to get type.
Let's try again.
That's it.
Everything compiled correctly.
And one thing that we can do here is to enable open EBP after run and run again.
And this time we can look to see if our reset logic from the driver initialized correctly.
The ready signal at reset.
So let's add the error and takes interfaces.
And you can see that takes already.
It's already high from the reset.
And let's also add actually the reset signal.
And you can see that when a reset starts our MD takes ready signal is assigned to value one.
And this means that our RTL will see that all the transactions started by it will finish immediately because it will receive this ready equal to one.
And this is what we see also on the waveforms.
Immediately when the master starts this transaction, it sees takes ready and moves forward.
So actually we can see the data going out of our RTL.
If we look here for example at this final data, this 24 here from the MD, Eric's interface goes out on this takes interface here just because we initialized the take signal to value one.
But we don't want this in our test, right?
We don't want to get the ready signal to be high all the time.
We want to have some control over the length of the items on the takes interface.
And in order to get this control, we also need to implement the sequencer and the sequences.
So let's do this.
Next let's implement the sequencer.
And the first thing that we will do is to reformat a little bit the code that we already have from the MD master driving logic.
So one thing that we will do is to rename the sequencer class to this sequencer base.
And then we will define this sequencer base master and use this one to create this sequencer master class.
So let's do this.
Let's rename this file cfs MD sequencer to Cfmd sequencer base.
And let's add this base name of.
Everywhere in this file.
That's it.
Now let's also fix the include.
And we actually use this sequencer class also in the agent.
So let's fix this.
And now let's go to the agent master where we did the override.
And finally in the sequencer master we actually used this one.
And let's replace it here.
And let's see if our code compiles with the changes that we did so far.
Let's unselect this show EP after run and see if we introduce any compilation issue we did.
Let's fix first this one.
That's right.
We also use this name when we declared the p sequencer in the sequence base class.
So let's fix this and try again.
Now everything compiled correctly.
Next let's declare this sequencer base master class.
That's it.
Now let's include this file.
And use this class as the parent of the sequencer Concert master.
And we don't really need any parameter here.
Let's see if our code compiles correctly.
Everything looks good.
We have no compilation issue, so we updated this master branch here.
And now let's implement this sequencer based slave in which we will declare that Fifo that we need and the port.
So let's do this.
Now let's include this file in order to check it for compilation issues.
That's it.
Now let's declare here the pending items Fifo.
So this Fifo takes as a parameter the type of data that we want to put in it.
And this will be the item moon class.
Next let's create an instance of this.
And we can do this in the constructor.
And its constructor takes three arguments.
The first one is the name, then the parent class, and then the size of this Fifo in.
In our case, we want the size to be one, because at any moment in time we can only have one item started by the master.
So the MD protocol is not allowing us to start a new item, while the previous one did not yet finished.
So this is why we need only one element in this Fifo.
Next, let's declare that implementation port on which we will receive information from the monitor.
And because we only need one implementation port here, we can actually use that base class of the analysis implementation UVM analysis IMP.
And this implies that also here we will have to declare that right function.
Let's create an instance of this port.
And let's declare that right function.
And what we want to happen when this function is called is.
First we need to see if the item sent by the monitor is the information collected at the beginning of the item, and we can do this by looking at the is active function.
And at this point, we know that we received the information from the beginning of the item.
And next we want to push that information in our pending items.
But before we do the push, we need to make sure that there is room in our pending items Fifo.
If there is already an item there, then this means that something went wrong, probably in the sequences, because already at this point that item should have been taken out from this Fifo.
So let's do that check.
So we will use the is full function from our UVM tlm Fifo class.
And if the Fifo is full then we trigger an UVM fatal message.
That's it.
Now, if the Fifo is not full, let's try to push this information in the Fifo.
And we can do this using a function called try put.
And this try put will return zero if the push to the Fifo was not successful.
So let's also check for this.
That's it.
Now the last thing that we need to do in this sequencer based slave is to clear our pending items at reset.
So let's do this.
And we can clear the information from these pending items Fifo by calling the flush function.
That's it.
Let's see if our code compiles correctly.
We have a compilation issue.
Let's fix it.
Here I forgot to put an E slave.
Let's try again.
We still have a compilation issue again.
I forgot here to put an pending items.
Let's try again.
Now.
This time everything compiled correctly so we can move forward to our sequencer slave.
And this one will be quite similar to our sequencer master.
So let's take the code from here and try to adapt it in our sequencer slave.
That's it.
Now let's include this file.
That's it.
Now let's override the sequencer used by the agent slave, just like we did here for our agent master.
That's it.
Let's see if our code compiles correctly.
Okay.
Everything compiled correctly.
We did not get any error.
Now, the last thing that we have to do in the agent slave is to connect that port from one from the sequencer to the one from the monitor.
And of course we can do this in the connect phase.
But because we might want in the future to disable this connection, let's do this in a separate function, which we will call in the connect phase function.
And by doing this we can allow some future extensions Actions of this agent slave in which that function is overwritten.
So let's do this.
That's it.
And if the casting is successful, we can connect the ports.
That's it.
Let's see if our code compiles and runs.
That's it.
Our code compiled and run successfully.
And now we should call this function in our connect phase here.
That's it.
Let's save and see what happens when we run our code.
That's it.
Our code compiled correctly.
But if we scroll up, we can see that now we get an UVM fatal.
And the error message that we get is the one that we wrote in the sequencer.
This one.
And let's go back to our sequencer to see exactly the condition for this error.
So the error message is this one.
And the condition is that we tried to push in our Fifo in our pending items Fifo while the Fifo was full.
And this is happening because of the following reason.
If we look on the waveforms, we can see that our 3D signal is high.
And again, this means that the RTL sees on the stakes interface that any slave connected there responded immediately.
So our monitor will send to the sequencer the first item here at the beginning of the first transaction, and then it sends another one here at the beginning of the second transaction.
So this time here it's 175 nanoseconds plus one.
Because remember the monitor samples the data after one nanosecond.
So at 176 nanoseconds our Fifo was already full.
And the monitor sent a new item to be pushed in this Fifo.
And we can see this also in the log.
We get the error message at 176 nanoseconds.
And the solution for this one is to Implement the slave sequences which will pull from our pending items Fifo, so it will keep the Fifo empty at this point in the simulation.
So let's do this now for the sequences.
Let's first update the inheritance tree on the master branch.
So we will create this base master sequence in which we will declare this sequencer.
And then we will use this sequence as a parent for this simple master sequence.
So let's do this first in the MD sequence base we should remove the sequencer from here.
And now let's create the sequence base master class.
And in here, let's declare that p sequencer of the correct type.
And now let's include the file.
And let's fix the parent class of our simple master sequence.
That's it.
And let's see if everything compiles and runs everything run correctly.
We did not get any compilation issue.
We still get this UVM fatal error.
But now let's try to fix this by first declaring the sequence base slave class.
And this one will be quite similar to the sequence base master.
And let's replace master with slave.
Let's include the file.
Now let's create the simple slave sequence.
And again, this one will be quite similar to the simple master sequence.
So let's take the code from here and adapt it to our needs.
Now let's include the file.
That's it.
Now let's create the slave response sequence.
And now, in order to pop the next item from our Fifo from the sequencer, we simply call the task get.
And this get task will wait until there is some information available in our pending items.
So this is why this is a task.
And once this get task is finished, we have access to the information sent by the monitor.
So let's use it.
And here we can write some constraints based on the information from the monitor.
But before that, let's also implement that slave response forever so that we can see some information driven on the bus.
But also let's not forget to include this file.
That's it.
Now let's create that slave response forever sequence.
And as we discussed, we will create here a forever loop in which we will start this slave response.
So let's do this.
That's it.
Now let's include this file.
And let's go to our test and start this sequence.
And we want to start this sequence in the background.
So we will use a fork.
Join none.
So we start this on the MDX agent sequencer.
So let's save and select open EP Wave after run and see how the waveforms look like.
Looking at the waveforms, I can see that we have a small problem with our slave driver.
You can see that after each transaction our slave driver drives back, takes ready to value zero.
But we had a field called radiate and in which we wanted to randomize these values.
So let's look in our driver and fix this problem.
And this should be at the end of our drive transaction task.
You can see here we are driving a ready equal to zero at the end of the transaction.
But let's make use of our field ready at end from item.
Let's save and run again.
Now the slave driver looks okay.
You can see this MDX ready signal going to zero after the first and the second transaction.
But it remains high after the third one and also after this last one here.
Now let's also look on the log to see if the printed messages from our slave driver are matching the information that we see on the bus.
So let's take for example this first transaction.
This one has a response equal to okay and a length of zero, 123 and four.
So let's see if we see this on the log.
This is the first message from our tax agent.
And you can see the length is equal to four.
And the response is okay.
So this one looks fine.
And to make things clearer when we are looking at the log, let's add a new message from our monitor to show us when the monitor started to collect the information on the bus and in the monitor, let's search for the beginning of collect transaction.
Just before we send to the port the collected information so far.
Let's copy this message and put it here and change it a little bit.
And let's try to run again and see when this message appears.
And when the driver starts to drive the information on the bus.
And let's look at the log and see this information.
You can see here this is the message from the tax agent monitor saying that it started to collect an item from time 166.
And immediately at the same simulation time, 166 nanoseconds.
Our tax agent driver printed this message saying that it started to drive this information on the bus.
So the communication between the monitor and the slave sequencer seems to work.
Okay.
Now let's check.
Also, let's say the last item driven on the bus by our tax agent.
And this one is, uh, this one from here.
So the last item driven should have a length of one and an error response.
And let's double check this on the waveforms.
This is the last tax transaction and it started here.
It has a length of one zero and one here.
And then response of error.
So our slave driver seems to work just fine.
Now let's try to add some constraints in our slave response sequence based on the information coming from the monitor.
And let's say that we want to send an error response only for an item with data 85.
So only for this one with data 85.
Here we want to respond with an error response.
And for the rest of the transactions on the stakes interface we want to respond with an okay response.
So let's do this.
Let's go to our slave response.
And in here we have access to the item coming from the monitor.
And let's apply such a constraint.
So at this point, we also have access to the data.
And we can simply constrain the response based on the data.
And let's see if our constraint worked.
So it looks like the constraint is working only for this transaction.
With data 85 we have an error response.
And for the rest of the transactions the response is okay.
And just before we end this tutorial, I just want to correct two mistakes that I did in the code.
The first one is in the sequencer bass master.
Here we don't need to use the UVM component param utils, just the uvm component utils, because this class has no parameters and the second one is in the sequencer base slave.
There is a typo here in this error message.
It should be no sequence.
And one final thing.
Before we finish, let's go back to our slave response sequence and comment these constraints.
Just because we want our test to be as random as possible.
Let's run again to make sure that our waveforms look okay.
And we did not introduce any compilation issues.
Everything looks okay.
The driving seems random and we can see actually data going in our RTL on this air interface and going out on the static interface.
For example, here, if we zoom, we can see this data one for FB and this goes out on this interface.
You can see this one for with this transaction here, and then FB in the next one.
So that's it.
We managed to implement the MD slave driving logic which was the most complicated we implemented so far.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
