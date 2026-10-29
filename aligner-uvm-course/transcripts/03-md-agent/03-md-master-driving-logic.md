# MD Master Driving Logic

*Chapter: MD agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to code together the MD Master Driving Logic.
The first thing that we will do is to code the MD item Drive Master, and after that we will code the sequencer and only the master side here.
Next we will code the simple master sequence with all its classes.
And finally we will code the MD driver and in particular the master side.
So let's get started.
First let's go to the item.
So we need to create this item base class, this item drive class.
And finally this item drive Master.
As always the starting point is the MD Master Driving Logic Practice Project, which we need to copy.
Let's resize the window and start coding the MD item base.
That's it.
We coded the item base and as you notice, we don't have any fields to add currently in this class.
But that's fine.
We can still have an empty class from which we can extend other classes.
Now let's include this file in our MD package.
Next let's create the item Drive class.
And this one will be quite similar to this item base.
That's it.
Now let's also include this file.
And now finally let's declare Our CFS MD Item Drive Masterclass.
Let's add the four fields that we talked about.
Pre item delay.
Post item delay data as a list of bytes and offset.
That's it.
Now let's try to add some constraints to these fields.
For the data we can add actually two constraints.
One which will be a soft constraint.
And we will constrain the data size to be equal to one.
Because we know that a data size equal to one will work in any configuration of the agent regardless of the data width value, and the other one will be a hard constraint in which we constrain the data size to always be bigger than zero.
And finally, let's also apply a soft constraint to the offset.
And again, just like for the data, we know that regardless of the data with parameter of the agent, an offset of value zero will always work.
So let's do this.
One thing to clarify here, of course we will want to run the test with other values for the offset and for the data.
And we can always disable these constraints from the sequence level and apply other constraints from there.
Now the last thing that we want to do here is to declare the function convert to string in order to get a nice information printed for this item.
So let's do this.
That's it.
So the special thing that we did in this function is just to create a nice string for the data, in order to print all the values from this list.
Now let's include this file also, and let's try to see if everything compiles and runs correctly.
So as always make sure that you unselect show output file after run.
And let's save and give it a try.
Everything compiled correctly.
We don't have any compilation issue.
Now let's move forward to the sequencer.
For the sequencer we will first create this base class SMD sequencer, in which we will copy paste from the APB agent the handle reset implementation.
And we will also declare this Getdata width function here.
And then we will implement this CFS MD sequencer master which will have as a parameter the data width.
And in here we will overwrite the implementation of the Getdata width in order to return the correct result.
So let's get started.
First let's create that CFS MD sequencer class.
That's it.
Now let's go to the app agent and take the handle reset implementation of the sequencer from there and see if we have to change anything.
That's it.
As you can see, the handle reset implementation has nothing to do with the agent that we are doing.
It's all the same.
So we're all good.
And finally, we have to declare that getdata with function.
That's it.
As I told you, we cannot declare this function as pure virtual.
So we need to declare here an empty body.
But just as a precaution, we can add here a check on UVM fatal message in order to remind us that we have to implement this function.
If we will forget this in the child classes of this sequencer.
That's it.
Now let's include this file and see if everything compiles correctly.
We do not have any compilation issue.
Now let's move forward to the sequencer master.
That's it.
So the master sequencer only implements this getdata width by returning the value of the parameter.
Now let's include this file and see if everything compiles.
Everything run correctly.
And now let's create an instance of our sequencer in the agent.
And as you can see here, we need to specify the type of the item used by this agent.
So we need here to specify if the item is either master or slave, item drive master or slave.
But we do not know yet in the agent what kind of item we need.
We will know this information in the agent master or in the agent slave.
So this means that we have to add here another parameter for the item drive.
That's it.
Now let's add this parameter also here and use it in the declaration of the sequence handler.
Now let's create the instance of this sequencer in the build phase.
That's it.
Now the only thing that we need to do is to overwrite this type here with our sequencer master.
And we can do this in our agent master.
That's it.
Now let's see if our code compiles.
Everything looks good.
We don't have any compilation issue, so we can move forward to the sequences.
For the sequences, we will create two classes.
This sequence base in which we declare that piece sequencer.
And then we will create this sequence simple master, in which we drive one item.
And also here in this sequence simple master, we will apply those constraints based on the getdata width from the sequencer.
So let's do this.
And now let's declare that sequencer here, which will be of type SMD sequencer with item drive as a parameter.
That's it.
Now let's also include this file.
And now let's create our sequence.
Simple master class.
That's it.
Now let's create an random item and apply those constraints over it.
So first we said that the data size should be bigger than zero.
Then data size should not be bigger than the data width of the bus in bytes.
And something similar for the offset.
And finally the data size plus the offset cannot be bigger than the data width in bytes.
That's it.
Now in the constructor we need to create the instance for the item.
Now remember in the item, we applied some soft constraints to the data size to be equal to one and to the offset to be equal to zero.
And this is fine if we don't apply any constraints from the sequence level.
But because we did we want to disable these constraints.
And we can do this here.
That's it.
Now the only thing remaining is to declare the body task of this sequence and to send the item to the driver.
That's it.
Now let's include this file.
And let's see if we have any compilation issues.
Everything compiled correctly so we can move forward to the driver.
For the driver, we will create this CFS MD driver class with a parameter, and we will take a lot of code from the APB driver.
And then we will declare this CFS, MD Driver Master class, in which we will only implement the driver transaction task.
So let's get started.
First let's declare the CFS MD driver class.
That's it.
Now let's go to the APB and try to take as much code as possible from the driver.
And let's put it here and try to adapt it for our needs.
The run phase is the same for the drive transaction.
We said that we will implement this in the driver master.
So let's remove all this code and only add an UVM fatal as a reminder.
Drive transactions.
It's mostly the same with the exception of the type of the item and then the rest of the code.
It's similar, except this part in which we need to remove this as we not yet know what signals to initialize here.
Let's align the code.
Let's try to search for the APB to see if we missed anything.
Yes, we still have it here.
We can get rid of this part.
Let's give it another try.
Okay.
We're all good.
Now let's include this file and see if we have any compilation issues.
And let's try to run the code.
We don't have any compilation errors.
So now let's move to our driver master class.
That's it.
Now let's declare that virtual interface type that we also declared here because we will need it.
And now let's implement our drive transaction task from the driver.
And I just noticed that the code is not really correctly aligned here.
So let's fix this.
That's it.
Now let's implement our drive transaction task from the driver class.
First let's do some checks on the information from the item.
So for example, we want to check that the offset plus the data size, it's not bigger than the data within bytes.
So let's do this.
That's it.
Now let's also try to include this file.
So we can try to run and see if we get any compilation issues while we are writing this file.
Okay.
And now let's give it a try to see if we did any mistake.
We did.
And let's see what it is and fix it.
The problem is in this macro I put here this one by mistake.
Let's remove it.
And now let's give it another try.
Okay, we're all good.
Let's move forward with the implementation of this task.
First, let's wait those pre-drive delay clock cycles.
Next, let's drive valid equal to one.
And let's try to create a field for the data with the data bytes correctly aligned based on the offset.
That's it.
So we have this data field.
And we align the information from the data list in this field based on the offset.
And now we can drive this information on the bus.
And we should also drive the offset and size.
Now we should move forward with one clock cycle and then simply wait to get as a response the ready signal.
That's it.
So we are here at the end of the transaction.
So we need to clear all the signals that we drove until now.
And finally we need to wait that post drive delay.
That's it.
Now the only remaining thing is to overwrite the handle reset.
And also make sure that we initialize the signals there.
Once the reset is finished.
Let's also make sure that we call the implementation of this function from the parent class.
And let's initialize the signals driven by the master.
That's it.
Let's see if everything compiles.
Everything looks good.
Now let's create the instance of our driver in the agent.
Next, in the connect phase, let's connect the sequence item port of the driver to the sequencer and also connect the pointer to the agent config inside the driver.
That's it.
Now the only remaining thing is in the agent master to override the class used for the driver.
That's it.
Let's see if our code compiles.
Everything compiles correctly.
Now, let's not forget to add as the second parameter of the MD agent our item.
Now, the only remaining thing in this tutorial is to see everything working together.
So we will create a random test in which we will drive four of these sequences.
Simple master to see that everything looks okay.
So let's do this.
And now let's go to our test rig access and try to take some of the code from here.
And let's simply create a repeat loop which will look something like this.
And we put it instead of this fork.
And in this repeat loop we will drive this sequence.
And when we randomize we don't apply any constraints.
Let's fix here the agent that we use.
And one special thing here is that we must remember that in the randomization we are making use of that get data width from the sequencer.
So when this happens we need to have a valid pointer connected to that sequencer.
And we can do this via a set sequencer function.
And we simply pass the pointer to the sequencer.
That's it.
So in this test we have this repeat for in which we send four of these sequences.
Now let's include this test random file in our aligner test package.
So here.
And let's also import the MD package.
And one final thing that we need to remember is to change in the run options under the UVM test name to put our random test because we had until now, our reg access.
That's it.
Now let's also select open EP Wave after run.
And let's try to run to see if on the waveforms we see the four transactions.
That's it.
Our simulation finished.
Let's first check to see if we have any errors.
We don't.
And in the log we are seeing some messages from our driver saying that it started to drive this item and this one and this one and this one.
So at least from the logs everything looks good.
We tried to drive four items and let's see on the waveforms if we see the correct thing.
So let's put the clock and then the MD Alex interface first valid then data offset size and then the response from the duty ready and error okay.
We have some accesses here.
So let's look at the first one.
It tried to drive offset two with size two.
And this data A0 and C0.
And we got an okay response from the RTL.
And let's see if in the log we also see this information.
A0 c0.
So we have this one a0.
The first element in the list c0 offset to and size.
Of course it's two.
And let's look at the another one let's say on this one with data three four and two nine from offset one.
And this means that for this one we should get an error because we cannot send two bytes from offset one.
So let's look on the waveforms.
This is the third axis.
Let's zoom in and you see three 4 to 9 from offset one.
And we also get an error from the RTL.
That's it.
For this tutorial we managed to drive some transactions on that ADCs interface.
So from our master MD agent thanks for watching and see you in the next tutorial.
Bye.
