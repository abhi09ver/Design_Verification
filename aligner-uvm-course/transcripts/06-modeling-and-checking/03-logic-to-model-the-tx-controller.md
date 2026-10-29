# Logic to model the TX Controller

*Chapter: Modeling and checking · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to implement together the logic to model the TX Controller.
This means that we will have to add in our model component all the API here represented with blue.
The starting point is the EDA Playground project called "Model TX Controller - Practice" which we need to copy.
And now let's resize the windows.
First, let's implement this set_tx_fifo_empty() function and let's copy the code from set_tx_fifo_full() and adapt it.
And that's it.
Next, let's implement this dec_tx_lvl() function.
And let's take the code from inc_tx_lvl() and adapt it.
That's it.
So we are decrementing the TX_LVL and if this one reaches value 0 then we are setting this TX_FIFO_EMPTY flag.
Now let's implement this pop_from_tx_fifo() task.
And let's take this code.
That's it.
So we are popping from our TX FIFO using this get() task then we decrement TX_LVL and we print this message.
And when we run our test we can use this message to determine if our logic is implemented correctly or not.
Next let's declare this tx_complete event.
So that's the declaration.
Now let's create an instance of this in the constructor.
That's it.
And now let's go to our handle_reset() function and reset this event.
So here.
And finally let's trigger this event and we can do this in our write_in_tx() function here.
We can determine if this item_mon is finished via that function is_active().
So let's do this.
And that's it.
If the item is finished then we trigger this event.
Next, let's implement this tx_ctrl() task.
That's it, so the logic is pretty simple, we have our forever loop in which we pop from TX FIFO, then we notify the scoreboard to expect this item on the TX interface and then we wait for the monitor to let us know that this item ended on the bus.
Next, let's add the pointer to our process for the tx_ctrl() task.
That's the declaration and now let's go to our handle_reset() and kill this task at reset.
And that's it.
Now let's add the last function this tx_ctrl_nb().
And let's take the code from this function and adapt it.
That's it.
And now let's start our tx_ctrl() task in handle_reset().
That's it.
And now let's try to save and run to see how our test is behaving with this new logic for the TX Controller.
And let's also enable the waveforms to see the MD TX interface.
That's it, our simulation finished.
And now first let's look in the log to see if we get our messages from the TX Controller logic.
Here there are, so the first message is this one TX FIFO pop with this data FE.
And later in the log we can also see that the TX monitor detected exactly the same data FE.
Then we pop from the TX FIFO this information 60 and then also later our monitor detects this 60.
And let's also see this on the waveform.
So let's add the MD TX interface.
So on the waveforms RTL outputs FE, 60, B4 and 3B.
And let's see what we are predicting in the environment.
So the first one is FE, then 60, then B4, and finally 3B, just like the RTL it's outputting.
So it looks like, at least looking on the waveforms and the log, that the RTL and the environment are aligned on the outputted data.
And with this we managed to reach a very important milestone in our environment: completing the model component.
So we implemented everything in this picture and we had to implement a very big API of our model component and even though there are a lot of functions and tasks implemented here, if we look from above none of those functions or at least most of them are not really complicated.
We have the group of setters for the flags in the Status register.
Then we have the groups of functions to either increment or decrement the counters.
So we have three counters.
CNT_DROP and then these two counters for the RX level and TX level.
We have our tasks to push and pop from the RX and TX FIFOs.
And the main logic of the model stays in these functions and tasks from here: build_buffer(), split(), align(), and tx_ctrl().
And for most of these tasks we follow the same pattern, we declare the pointers to their processes, and we allocate those pointers in these non-blocking functions here.
And we use the pointers to the processes in order to kill them in handle_reset().
Now we can use our model to feed the expected information in our scoreboard.
However, we will discover in later tutorials that there are some small problems with our model and these problems will be revealed when we implement also the scoreboard.
So once we discover those problems, we will come back to our model and fix them.
You might have noticed some of the problems when we coded the model, but if you didn't, don't worry about it as we will talk about all those problems in later tutorials.
I can give you a clue where those problems are and it has something to do with synchronization.
That's it for this tutorial.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
