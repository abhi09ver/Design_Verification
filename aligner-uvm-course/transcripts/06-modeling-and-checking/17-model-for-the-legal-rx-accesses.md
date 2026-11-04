# Model for the legal RX Accesses

*Chapter: Modeling and checking · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to implement together the model for the legal RX Accesses.
This imply that we have to add to our Model class the properties that we discussed in the previous tutorial and those are represented here with blue.
The starting point is the EDA Playground project called "Model Legal RX Accesses - Practice" which we need to copy.
And now let's resize the windows.
The first thing that we will add is the model to our RX FIFO.
So let's do this here.
So that's the declaration.
Our RX FIFO is of type uvm_tlm_fifo and the type of information that we will push and pop from this FIFO is this one: cfs_md_item_mon.
Now let's call its constructor and remember that we have to use for the size value 8.
That's it.
Now let's flush the content of our RX FIFO in the handle_reset() function.
That's it.
Now let's implement first this function set_rx_fifo_full().
And we can implement it just below this set_max_drop().
So let's do this.
That's it.
The implementation of this function is quite similar to what we imlemented for the set_max_drop().
First, there is this predict() with value 1 to this RX_FIFO_FULL register field from the Interrupt Request register.
Then there is this message telling us that the RX FIFO became full and also this message tells us if this RX_FIFO_FULL interrupt is enabled and if it is enabled then we know that we should inform the scoreboard to expect an interrupt request pulse on that interrupt request output of the DUT.
Next, let's implement this inc_rx_lvl() function.
And we can implement this function right under this inc_cnt_drop() here.
That's it.
So this function increments the mirrored value of the RX_LVL field and then if after the incrementation the RX_LVL is equal to the size of the RX FIFO, we call this set_rx_fifo_full() function.
Next, let's implement this push_to_rx_fifo() task.
And we can implement this task just under this inc_rx_lvl() function.
So let's do this.
That's it.
So in this task first we are pushing to our model of the RX FIFO using this put() task and remember that this one will wait until there is room in the RX FIFO.
After that we increment the RX_LVL, we have this message and at the end we inform the scoreboard that it should wait for an OK response.
So this is how we also model that delay on the MD RX interface where the RTL will delay the "ready" signal.
We send this information to the scoreboard only after the push to RX FIFO was successful.
And remember from the previous tutorial that this delay of this put() task from the RX FIFO is the reason why we are using that uvm_tlm_fifo class.
Next, let's implement this kill_process() function and for this we can go up and just above our handle_reset() function here we can declare this function.
That's it, our function receives as a reference a pointer to a process and if the pointer is not null then we call the kill() function on the process and then we set it to null.
Next, let's declare a pointer to the process of the push_to_rx_fifo() task.
So this field here.
That's it.
Now let's make sure that we kill this process in the reset function.
So here just above the rx_fifo.flush() we can call that kill_process() function.
That's it.
So this will kill any process associated with this push_to_rx_fifo() task.
Next, let's implement this last function push_to_rx_fifo_nb().
That's it.
So the implementation is pretty simple.
First we make sure that the process is null at this point otherwise it means that we have two instances of this push_to_rx_fifo() started.
Then in a fork - join_none we allocate this pointer, we start our task and at the end of the task we set again the pointer to the process to be null.
Now the only remaining thing is to finish the implementation of this write_in_rx() function.
And instead of this comment here we simply call this push_to_rx_fifo_nb().
And that's it.
Now let's try to test a little bit our code and for this let's go to our random test.
And in here let's add a legal access.
So let's copy this code and make it a legal access.
That's it.
So after these two illegal accesses we are sending this legal access and now when we run we should see in the log that message which says that our RX_LVL is incremented to value 1.
Our simulation finished and now let's look through the log to see if our model is working correctly.
And here is our message "RX FIFO push - new level equal to 1".
So it looks like a first try of our logic is working correctly.
That's it for this tutorial.
We managed to implement the logic for modeling the legal RX accesses.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
