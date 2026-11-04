# MD slave Driving logic

*Chapter: MD agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to talk about the EMD slave Driving logic.
This is the current state of our verification environment and in this tutorial we are going to talk about the sequencer and the driver from the EMD slave agent when it comes to driving.
The first thing that we need to figure out is what kind of information to put in, the item with which the driver will work, and for this, we need to see how the EMD transaction looks like on the waveforms.
So the first thing that we can control from the slave driver is the length of the EMD transaction.
This means the number of clock cycles.
It will take the driver to drive this response back to the master.
This length will be an unsigned integer, and a value of zero will mean that the EMD transaction will be one clock cycle long.
A value of one means that the EMD transaction will be two clock cycles long and so on.
Another obvious field that we can add in the item is the response.
So the value of the error signal.
And the third item that we can have is the value of ready signal at the end of the transaction.
And we need such information here because we might want to drive something like this.
So we will drive ready low at the end of the transaction.
Or we can keep driving ready to value one, just like we have here.
And we need this in order to model some RTL implementation in which the ready signal is connected to the full signal of some internal Fifo.
So in that case, ready will be kept high as long as the Fifo is not full.
And with these three fields, our class definition of the item will look something like this.
We will have the length response and radiate end and our UML diagram of the item looks something like this.
In the item drive slave, we will have these three public fields.
Now that we clarified what we want to drive with our driver, we need also to understand when to drive this information on the bus.
If we were to implement the slave driving logic, just like we implemented the master driving logic, then this means that we can drive that information randomly from the time point of view, so we can start the sequence whenever we want.
But let's see what this means when we look on the waveforms.
So let's say that at this point in time, we decided to drive on the bus an item with length three and response error and radius end zero.
When our driver logic receives this information at this point in time, there is no item started by the master, so our driver will have to wait up to this point, and from this point forward it can drive.
This information.
So it will drive the ready response here.
And this is because of our length equal to three.
So remember that we will count something like this 012 and three.
And we will also drive this response error here.
But if we look at the transaction that the master drove we can see that the offset is two and the size is one.
And if we consider the same rules as our aligner RTL, we might want to drive for such a transaction an okay response.
But we cannot do this if we start the item all the way here, because at this point we already generated the response equal to error.
And at this point we don't know yet what the master will drive.
We only find out this information two clock cycles later.
So sending the information at random points in time really limits our capability to control correctly this interface.
And here's another example of our limited control over this interface.
If we decide to send this information at random points in time, let's say that at this point in time, we decide to send an item with length zero.
So at this point, the master already started to drive a transaction all the way from here.
And because we want to drive an item with length zero, this means that we will start to drive the response immediately when the item reaches the driver.
So we will get a waveform just like this one.
But this is a big drawback because this item on the waveforms looks exactly the same in this scenario and also in this scenario.
But in the second one, we actually want it to drive an item which looked something like this, but we only get this part here.
So it's obvious that with the slave agent sending the information to the driver at random moments in time gives us poor control over the MD transactions.
One solution to this problem is to make use of our updated logic from the monitor.
Remember that now in our MD monitor, we are sending the information at the end of the item, but also at the beginning of the item.
And we can make use of this moment when our monitor sends the collected information at the beginning of the item to synchronize our sequences and to decide when to send the item.
And let's see how we can make use of this.
So let's say that we are here at the beginning of the MD transaction, one nanosecond after the rising edge of the clock.
So at this point our monitor will send via the output port information like the data and the offset.
If we get this information in our sequence, then we can generate an item based on this information.
So we will know that the offset is two and the size is one.
And this means that we can constrain the response that we will send to the driver to be an okay response.
And once we have this item generated, then we can send it to the driver.
And we will drive a response for this transaction as we want it with an okay response.
This approach can also work if we decide to send an item with length zero, because at this moment we are here at the beginning of the transaction, we still have time to drive an response with length zero.
Just be aware that our driver in this case will start to drive these signals one nanosecond after the rising edge of the clock.
So we will have this delay.
And now let's see how we can implement such a synchronization mechanism between the monitor and our sequences.
If we look at the diagram of our testbench, we realize that we have a little bit of access problem.
Our sequences and items actually live inside the test.
So they live outside our agent, and we don't have an easy access to the monitor from the sequences.
And not only that, but remember that we want to connect to the output port of our monitor, which is an UVM analysis port, and to connect to that port, we need to have an UVM analysis implementation port and that implementation port needs in its constructor a pointer to an UVM component.
But the sequences are not UVM components.
These are UVM objects.
And if we need a component to connect to the output port of the monitor.
Then the obvious candidate in which to place that port is in the sequencer, because in the agent, we have easy access to both the monitor and the sequencer in order to connect these two ports, and also in the sequence, we have access to the sequencer via that sequencer pointer.
So we will implement in the sequencer an analysis implementation port.
And when we receive information through that port, we will put that information into some Fifo.
And we can actually implement this Fifo using a class already defined in UVM.
It is called uvm dm Fifo.
And from this sequence we can pull information from this Fifo.
In order to know what kind of information the master started to drive.
And based on that information, we can generate our MD slave item.
So let's see a small animation with the flow of information in such a scenario.
So our monitor will create this monitor item will send it through the output port all the way to the sequencer.
And in here in the sequencer we will push it inside this Fifo.
And then our slave sequence will take this information from here and use it to generate an MD slave item.
And this item will be sent via the sequencer to the driver and then to the RTL via the interface.
So this is how we will synchronize the slave item sent to the driver using the information from the monitor.
But now let's open the UVM documentation and look at this Fifo that we will implement with a class from there.
So this is the UVM class reference documentation in the HTML format.
And if we go to the TLM, TLM one.
And then we have this chapter five four.
We find here this class that we will use UVM, TLM, Fifo.
And if we go to this class definition we get here some short description about this class and the API of this class.
And you can see here that the API is quite short.
We have a constructor and then we have some function for size.
If it is used it's empty it's full and flush.
And let's jump to the constructor.
And if we click on the name of the function, we can actually open the file in which this function is implemented.
So it is in this uvm tlm Fifo file.
And we can see here our class UVM, TLM, Fifo.
And one thing that I want to make you aware of is the following.
In here we can find the functions which were described in the documentation.
But there are still more functions like put to push the data in the Fifo or gate or peak and all this stuff here, which for some reason do not appear in our UVM documentation, but just be aware that they exist and we will use some of the functions and tasks of this class.
But now that we clarified this mechanism, which we will use in order to send items to the driver, let's see how this affects the inheritance tree of our classes.
Remember that when we discussed the MD master driving logic, we said that the sequencer inheritance tree will look something like this.
And we have here this CFS MD sequencer slave.
So this means that we can declare here our Fifo.
So this will be this field pending items and our port, and it will be this port from Mon.
And of course because this is an implementation port, it will also have a right function.
But if we were to declare these fields here in this class, this means that if we were to get a pointer to this sequencer in our sequences, it means that from there we will have to specify the value of the data width in order to be able to cast our sequencer pointer.
And this is exactly the problem that we wanted to avoid when we build the master sequencer, in which we declared this getdata width here in this class, which did not had as a parameter the data width.
And we implemented the function here in this sequencer master with a parameter.
So we can do something similar.
Here we can create an intermediate class sequencer based slave without the data width as a parameter.
And in here we will declare these fields, and it will be much easier for us in the sequences to get a pointer to the sequencer, which will be of this type in order to access these fields from here, and just to keep things uniform, we will also declare for the master this intermediate class base master, which will be empty for us.
And then from this one we will create our Midi sequencer master.
And also because these two classes will have this base name here, let's also rename our Midi sequencer to CFS Midi sequencer base just to keep things nice and uniform.
So this is how our inheritance tree of the sequencer will look like.
Now let's see how this affects our sequences.
Inheritance tree.
Remember in the MD Master Driving Logic tutorial, we discussed about this inheritance tree for our simple master sequence.
And one thing to notice here is that we declared the P sequencer in this MD sequence base, and we declared it of this type.
But what we can do is to remove this P sequencer from here and implement also an intermediate class for our sequences.
So we will add this sequence base master.
And in here we will declare this p sequencer pointer which will be of this type MD sequencer base master.
And we can do the same thing for our slave.
We will have this sequence base slave class.
And in here we will declare this P sequencer to be of this type for the master.
We don't really have any advantage if we do this, but for the slave, this means that we have this p sequencer of the correct type in order to access that pending Items Fifo from our sequencer.
So remember that we need access to that Fifo in order to be able to pull items sent by the monitor.
And for the slave part we will implement three sequences.
First, we will implement this simple slave sequence in which we just send an item to the driver.
Then we will implement this slave response sequence.
And this slave response sequence will be the one which will wait for the monitor to put some information into our Fifo from the sequencer.
It will pull that information and then it will generate this simple slave sequence.
And in here we can constrain the item that we will send to the driver based on the information coming from the monitor.
And because we want to do this for all the items started by the master, we will create this third sequence slave response forever, which will simply be a forever loop in which we will start the slave response sequence.
The driver inheritance tree will not change.
We will also have this MD driver slave which will inherit from this CFS MD driver, and in this one, we will only implement our drive transaction task in which we will drive that information.
That's it.
For this tutorial we talked about the MD slave driver item.
We talked about the slave driving mechanism, and we touched a little bit on the API of our UVM, DM, Fifo.
And then we discussed about the updates that we will have to do to the inheritance trees of our sequencers and sequences.
In the next tutorial, we will implement all these things together in the code, and I hope that everything will be clear for you once you will see it implemented.
Thanks for watching and see you in the next tutorial.
Bye!
