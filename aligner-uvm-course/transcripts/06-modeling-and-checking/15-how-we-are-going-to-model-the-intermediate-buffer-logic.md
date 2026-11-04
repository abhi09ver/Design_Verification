# How we are going to model the intermediate buffer logic

*Chapter: Modeling and checking · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about how we are going to model the intermediate buffer logic.
This is the block diagram of our model component with the API that we implemented so far and in this tutorial we are going to focus on this part of the model.
And let's see a short animation on the behavior of our RTL in this scenario so that we understand better what we need to implement.
This is the block diagram of our RTL and above we have three relevant registers for our scenario.
This one is the Status register, then we have the Interrupt Requests register and finally the Control register.
In the logic to model the intermediate buffer, we will model two register fields, the RX_LVL and the RX_FIFO_EMPTY.
And let's see how these fields will have to change in this logic for the intermediate buffer.
Let's say that in our RX FIFO we have three entries.
This means that the RX_LVL is 3 and RX_FIFO_EMPTY is 0.
Now the logic inside the Controller which dictates when to pop information from the RX FIFO is based on this formula.
The Controller will pop information from the RX FIFO until in its intermediate buffer the number of bytes will be greater than the SIZE field from the Control register.
In this way the Controller ensures that it has enough bytes for the alignment logic to align these bytes.
So let's see how this popping is done and how these fields evolve with each pop.
So let's assume that our SIZE field is 4 and OFFSET is 0.
At this point, the Controller has no bytes inside so it will pop the first entry.
This will decrement the RX_LVL as the RX FIFO has now only 2 entries inside and the RX_FIFO_EMPTY, of course, will remain 0.
So because the Controller now has inside only one byte which is smaller than the SIZE field, 4, it will continue to pop.
After the second pop, the RX_LVL is decremented to 1 as there is only one entry in the RX FIFO.
Now the Controller has inside its intermediate buffer 3 bytes, which again is smaller than the SIZE field, so it will continue to pop.
After this third pop inside RX FIFO there are no more entries so RX_LVL will become 0 and RX_FIFO_EMPTY will become 1.
Now the Controller has inside 7 bytes which is greater than SIZE so it will not try any new pops from the RX FIFO.
And let's say that at this point we have a new MD transaction going inside our RX FIFO.
So at this point the RX_LVL will be incremented to 1, but the RX_FIFO_EMPTY flag will remain 1 as the implementation of this flag is sticky.
This means that even after the condition which triggered the interrupt is gone, the interrupt will still remain equal to 1.
And only when the software clears this interrupt, then this flag will become 0.
So this is how these register fields will change.
And now let's go back to our Controller logic.
So at this point, even if there is a new entry in the RX FIFO, the Controller will not pop it from the RX FIFO because it has inside 7 bytes, which is greater than 4, the value of the SIZE field.
So in this scenario, the Controller will wait for the alignment logic to process some of the bytes from here before popping a new entry from the RX FIFO.
So that's the logic that we want to model in our model component.
And now let's see what we need to add in the API of our Aligner model in order to implement this logic.
The first thing that we will have to add is a model of this intermediate buffer.
For this buffer we don't really need the uvm_tlm_fifo, we can simply define it as a SystemVerilog queue of type cfs_md_item_mon.
And this one needs to be declared as protected as there is no need for some external logic to modify this buffer.
And while we are on this subject, let's also correct an error from the previous tutorial.
We declared our rx_fifo model as public, but there is no need for this one to be public, we can declare it as protected, as there is no need for the external logic of the model component to access the rx_fifo.
The next function that we need to declare is this one: set_rx_fifo_empty().
Obviously with this one we will set this RX_FIFO_EMPTY flag to value 1, just like we did for this RX_FIFO_FULL.
Next, we will need a function to decrement the RX_LVL from the Status register.
To pop information from our RX FIFO we will have to declare a task called pop_from_rx_fifo().
Obviously this one needs to be a task as it will call that get() task from the uvm_tlm_fifo and the popped result will be placed in this item argument here declared as a reference.
This logic to model the intermediate buffer will have to make sure that it will try every time to have in this intermediate buffer enough bytes for the alignment logic to work.
This means that we will have to implement a forever loop which will continuously try to pop from the rx_fifo as long as there are not enough bytes in this intermediate buffer.
And we will implement this forever loop in a task called build_buffer().
And one thing to pay attention in this forever loop, when there are enough bytes in this intermediate buffer, this logic will have to wait one clock cycle.
So we will have to bring in our model a virtual interface to access the clock signal.
As I told you, this build_buffer() will contain a forever loop so this task will never end.
But we want to be able to manage the process of this build_buffer() task.
And for this, we will have to declare a pointer to its process.
And this one, we will name it process_build_buffer.
The main thing that we want to do with this process pointer is kill it at reset and then restart it once the reset is ended.
And to allocate this process pointer we will have to declare a function called build_buffer_nb() in which we will allocate that process pointer and then we will start this build_buffer() task.
So, as in the previous tutorial, these with blue are the new things that we will have to add in our model component but beside this update we will also have to update our environment config class.
In here, we will have to add a virtual interface with the getter and the setter and we will have to declare a very simple interface with only the clock signal as the input.
And we will take this interface via the environment config pointer from our model component.
In later tutorials, we will add more signals in this interface but so far we only need the clock signal.
That's it for this tutorial.
We talked about the logic to model the intermediate buffer and the new API that we will have to add in our model component.
In the next tutorial, we will implement all this together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
