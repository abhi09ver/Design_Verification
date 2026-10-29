# How we are going to model the legal RX accesses

*Chapter: Modeling and checking · source: attached*

Hi!
My name is Cristian Slav and in this tutorial, we are going to talk about how we are going to model the legal RX accesses.
This is the block diagram of our model component and its currently implemented API.
And in this tutorial, we are going to talk about this part here, the OK responses on the MD RX interface and the model of our RX FIFO.
This is our Aligner with its Status register and in order to better understand this functionality, let's look at the block diagram of our RTL.
And for this scenario, we also need to look on the Interrupt Request register.
And we will model two register fields, the RX_LVL from the Status register and the RX_FIFO_FULL from the Interrupt Request.
These two register fields initially are zero and let's see how these are changing when we are receiving transactions on the MD RX interface.
Let's say that we have a transaction with size 1 at offset 0.
So this one is a legal transaction and it will pass the RX Controller and go into the RX FIFO.
So at this point our RX_LVL is incremented to value 1 and this incrementation will continue for all the legal RX transactions that we will receive on the MD RX interface.
Of course, as long as the Controller will not pop information from our RX FIFO.
But in this particular case our RX_LVL will be incremented to value 2.
And in this case it will be incremented to value 3.
And let's see what is happening when the FIFO will reach its maximum level.
So here when the RX FIFO level is 7, let's say that we are receiving a new RX transaction and when this one goes into the RX FIFO, the RX_LVL will be incremented to value 8 and the RX_FIFO_FULL will become 1.
And remember that these interrupts from the Interrupt Request register are sticky interrupts.
This means that they will remain to value 1 even after the condition which triggered them is gone.
So for example when the RX FIFO will no longer be full, this interrupt will still be 1 until the software clears it.
But coming back to our RX FIFO, there is one more thing to mention here.
When the RX FIFO is full, if we have a new transaction on the MD RX interface, the RX Controller will prevent this transaction to be completed as long as the RX FIFO is full.
So we will see on the MD RX interface that "ready" signal remaining low, to value 0, as long as the RX FIFO is full.
So we will have to keep this in mind when we will model this behavior in our model component.
And now let's look at the API of our model component to see what exactly we need to add in order to model this behavior.
The first thing that we will have to add is a model of our RX FIFO.
And we will model this RX FIFO with a class which already exists in the UVM package and this class is called uvm_tlm_fifo.
And let's have a quick look over the API of this class which we will use in our model.
The inheritance tree of this class is this one.
Our uvm_tlm_fifo inherits from uvm_tlm_fifo_base which is an UVM component.
The FIFO class has a parameter which holds the type of the information that we want to push and pop from this FIFO.
And let's see the functions and tasks of this class that we will use.
The first function that we will use from this class is the constructor, new().
And one important thing for us to see here is that beside name and parent, we also have the size.
So we will configure in the constructor the size of our RX FIFO.
And in our case, we will use value 8 for the size.
The next thing that we will use from this class is the task put().
This put() task is the way we will push information into our RX FIFO.
And the important thing to remember here is that this put() is a task, which means that it will consume time.
And the scenario in which this put() task will consume time is when the RX FIFO is full and we want to put new information in the FIFO.
This put() task will wait until there is room in the RX FIFO to put that information.
And this is exactly the behavior that the RTL has when the RX FIFO is full.
It will not return the ready response on the RX interface.
So this is a very important thing for us to model in our model component and as you can see this uvm_tlm_fifo already provides this feature for us.
So we can use right out-of-the-box.
A similar behavior is on the other side when we want to pop information from this RX FIFO.
There is a task in the uvm_tlm_fifo called get().
And we use this task in order to pop information from the RX FIFO, but this task will wait if the RX FIFO is empty.
And when there is some data in the RX FIFO, this task will end and it will provide in this "t" output argument that information.
Another function that we will use from this uvm_tlm_fifo is the flush() function.
As its name suggests, when we call this function it will flush all the entries from the FIFO and we can use this function in the reset logic of our model.
And the last function that it will be of use for us is the function size() and this one will return the size of the RX FIFO.
Just keep in mind here that it will return the capacity of the FIFO not the number of elements inside the FIFO.
And now let's go back to our model component and see what else we need to add here.
The next thing that we will need to add in our model component is a task called push_to_rx_fifo().
This one needs to be a task because we will call that put() task from the RX FIFO.
But this push_to_rx_fifo() task will have to be triggered by this write_in_rx() function.
Remember that this write_in_rx() function is called by our MD RX monitor whenever it detects some transaction on the interface.
But in order to start a task from a function we need to wrap the call to that task in a fork - join_none.
And in this way we will start the task in the background.
And for this we will have to put that fork - join_none in a new function called push_to_rx_fifo_nb() from non-blocking.
So this will be the function which will start our push_to_rx_fifo() task.
But we want to be able to manage that background process, so we will have to declare a pointer to that process and we will call this process_push_to_rx_fifo.
There are two things that we want to do with this pointer to this process.
First, we want to make sure that there is only one instance of this task started at any point in time.
And this is because the MD protocol does not allow overlapping transactions.
So it would be impossible to have two push_to_rx_fifo() tasks running in the same time.
The other thing that we want to do with this process pointer is to be able to kill it at reset.
And in order to make things easier when we want to kill a process, we will have to declare a function called kill_process() and this one will receive a reference to a process and then it will kill that process.
The next function that we will have to implement is called inc_rx_lvl().
Of course this one will have to increment this RX_LVL register field from our Status register.
And we will call this function from our push_to_rx_fifo() task once the push to RX FIFO was successful.
And the last function that we will have to implement is this set_rx_fifo_full() in which we will set to 1 this RX_FIFO_FULL flag from our Interrupt Request register.
So these with blue are the new things that we will have to add in the next tutorial in our model component class.
And before we close this tutorial, let me show you where you can find more information about that uvm_tlm_fifo class.
Of course, you'll have to look in the UVM Class Reference and in here there is a chapter under the "TLM Interfaces", "TLM 1", here you have this FIFOs section and in here you'll find more information about this uvm_tlm_fifo class.
And you'll find the description of the API of this class here.
And also, if you click on this uvm_tlm_if_base, it will jump to the section where you will find the description of the put() task, get() task, and so on.
That's it for this tutorial.
We talked about the new functions and tasks that we will need to add in order to model those legal RX accesses.
And we also talked about the API of the uvm_tlm_fifo class and its documentation.
In the next tutorial, we will implement all this together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
