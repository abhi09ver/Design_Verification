# How we are going to model the TX Controller logic

*Chapter: Modeling and checking · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about how we are going to model the TX Controller logic.
This is the block diagram of our model component with the API that we implemented so far and in this tutorial we are going to talk about this last part of our model component, the TX Controller logic.
And to better understand the logic that we need to implement, let's see a short animation.
And for this we will use the block diagram of our RTL and the three relevant registers for us: the Status register, Interrupt Requests register, and the Control register.
For this TX Controller logic, we will model two register fields: TX_LVL and TX_FIFO_EMPTY.
And for our example, let's consider that in the TX FIFO we have two entries.
This means that the TX_LVL is 2 and TX_FIFO_EMPTY 0.
The job of this TX Controller module is to try to continuously pop from the TX FIFO entries and drive them on the output interface.
So this is the MD TX interface.
So this means that our TX Controller will take the first entry from the TX FIFO, so at this point the TX_LVL will be decremented to 1 and the TX Controller will start to drive this information on the MD TX interface, and of course it will have to wait for any entity connected on this interface to acknowledge this data.
And this acknowledge is given by that "ready" signal of the MD interface.
And once this is done, the TX Controller is free to take a new entry from the TX FIFO.
So in our example here, the TX FIFO contains no entries, so the TX_LVL is decremented to value 0.
And of course the TX_FIFO_EMPTY flag will become 1 and inside the TX Controller the same thing will happen it will start to drive this information and it will end its job when that data is acknowledged.
So this is the entire logic in this TX Controller module and now let's see what API we need to add in our model component in order to implement this behavior.
The first thing that we need to add is a function called set_tx_fifo_empty() which will set to 1 our TX_FIFO_EMPTY flag from the Interrupt Requests register.
The next function that we will have to implement is this dec_tx_lvl().
Obviously this function will decrement this TX_LVL register field from our Status register whenever we pop new information from the TX FIFO.
And just like before, in order to pop information from the TX FIFO, we will have to implement this task called pop_from_tx_fifo().
And the result will be placed in this item argument declared as reference.
Now remember from our previous animation that the logic inside this TX Controller will have to pop information from the TX FIFO and then wait for that information to be acknowledged on the MD TX interface.
Of course, we will implement this in a forever loop, so we will have to make that forever loop wait for that acknowledgement.
And we can introduce this waiting in our forever loop via an event.
And we can declare an event called tx_complete.
This event will be emitted every time we detect an end of a transaction on the MD TX interface.
To model this event, we can use the native event from SystemVerilog, but I think this is a good time to introduce a new class from the UVM package called uvm_event.
This is a class wrapped around the native event from the SystemVerilog which brings new functionality to this event logic.
And let's see the API that we will use from this uvm_event class.
First of all, the inheritance tree, our uvm_event class, inherits from uvm_event_base which is an UVM object.
One important thing for the uvm_event is that it has a parameter and this parameter contains the type of the data that you can pass using an uvm_event.
This is a very useful feature of this uvm_vent class and I strongly recommend you to go through the documentation and see what API we have for this uvm_event when it comes to passing data.
But in our case, we don't need to pass any data, so we will not use the functions and tasks associated with this feature.
But let's see what we will use.
So the first thing that we will use is the constructor in order to create an instance of this uvm_event.
Then the next thing will be the function reset() part of the uvm_event_base and we will call this reset in our handle_reset() function.
Next, in order to emit the event to trigger it, there is a function called trigger() and we will call this when we detect the end of the MD TX transaction.
And finally, the last task that we will use is this wait_trigger() which waits for the event to be triggered.
So we will use this wait_trigger() in our forever loop which will model this TX Controller to wait for this event.
You can find more information about this UVM class in our UVM Class Reference Manual.
So if you go to Synchronization Classes, there is this section called uvm_event.
And you'll find here the API of this uvm_event_base and uvm_event.
And from my point of view, there are two important features of this uvm_event.
First, you can pass some data when you emit or wait the event.
And then the other relevant feature is that you can add callbacks to be triggered when the event is emitted.
So my recommendation is to have a look through this documentation and be aware of the features of this very useful uvm_event class.
Now let's go back to our model component and see what else we need to add here in order to model this TX Controller logic.
Now that we have an event to synchronize our logic when a transaction is ended on the TX interface, then it means that we can implement this tx_ctrl() task which is the main task implementing this logic.
And in this task we will have a forever loop which will continuously try to pop from our TX FIFO and then wait for this tx_complete event.
And just like before, we want to control the process of this task, so this means that we will have to declare a process pointer called process_tx_ctrl.
And to allocate this process, we will declare a function called tx_ctrl_nb(), which will allocate that process pointer and start our tx_ctrl() task.
And that's everything that we will have to add for this TX Controller logic.
That's it for this tutorial.
We talked about the new API that we will have to add in order to model this TX Controller logic and we also talked about this uvm_event class.
In the next tutorial, we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
