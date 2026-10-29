# Model for the align logic

*Chapter: Modeling and checking · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to implement together the model for the align logic.
This means that we will have to add in our model component all the new API represented here with blue.
The starting point is the EDA Playground project called "Model Align Logic - Practice" which we need to copy.
And now let's resize the windows.
The first thing that we will have to add is this model of our TX FIFO.
So let's go to our model and add this tx_fifo just like we did with the rx_fifo.
So that's the handle declaration.
Now let's create an instance of this.
That's it.
So the FIFO size is also 8 just like for the rx_fifo.
And now let's go to our handle_reset() and flush the content of our tx_fifo at reset.
And that's it.
Now let's add this set_tx_fifo_full() and this one will be quite similar to what we implemented for the RX FIFO.
So we can copy this code from here.
And let's add it here.
And that's it.
Next, let's implement this inc_tx_lvl().
And let's copy this inc_rx_lvl() function.
And adapt the code to our needs.
So this will be TX_LVL.
That's it.
Now let's implement this push_to_tx_fifo() task.
And let's copy the code from push_to_rx_fifo() but we will have to delete this line at the end.
That's it.
So we are pushing to our model of the TX FIFO then we are incrementing the TX_LVL and then we are printing this message.
And when we will run our test, if we see this message printed, then this will be a clue that our logic is implemented correctly.
Next, let's implement this split() function and we can add this function just below this build_buffer() task.
So here.
That's it.
So let's look through the logic of this function.
First I'm checking if the num_bytes has a legal value so it cannot be 0 or greater or equal to data.size().
Then we have this for loop with two iterations, one for each of the splitted item. and in here I'm declaring this splitted_item and based on this "i" I'm setting the offset and data so for the first item the offset will be equal to item.offset and the data will be the first bytes in this item.data and for the second item the offset will be offset plus num_bytes and the data bytes will be taken from the end of this item.data queue.
Then for both of the splitted items I'm copying the same information, prev_item_delay, length, response and finally I'm setting the begin_time and end_time in both.
And at the end, I'm pushing this splitted item in the results in items.
So the main thing is this if-else condition from here in which we set the offset and data different for these two splitted items.
Next, let's implement this align() task.
And we can implement it just above this split() function.
So let's do this.
That's it.
Now let's go a little bit through the logic of this task to understand it better.
So in this align() task I have this forever loop as the logic must always be active and in here I'm taking the values of the field's SIZE and OFFSET from the Control register and then I'm waiting this uvm_wait_for_nba_region().
This is a task defined in the UVM package and this allows us to this logic just a little bit in front of the positive edge of the clock.
And I want to do this in order to give a chance to that build_buffer() task to have time to push data in our intermediate buffer.
So we will see that at the same positive edge of the clock, first the build_buffer() task will push data in the intermediate buffer and then after this uvm_wait_for_nba_region(), our align() task will pop that information from the buffer.
So that's the role of this task here.
Then there is this if condition to test if there are enough bytes in the buffer so that the align logic can align them.
So the number of bytes must be at least equal to the CTRL.SIZE.
Otherwise, we are waiting the next positive edge of the clock.
But if the condition is true, then we have this while loop with the same condition.
And in this while loop, the logic will try to align the bytes as long as the condition is true.
And in this while loop, the first thing is to create the item which will contain the aligned data, this tx_item.
I'm setting the offset of this tx_item to the value of the OFFSET field from the Control register.
I'm setting its begin_time to be equal to the begin_time of the first entry in our intermediate buffer.
And then again, a new while loop which stops only when there are enough bytes in this tx_item.
So I'm looking at this SIZE register field from the Control register and in this while loop we have the align logic.
And the align logic, it's pretty simple.
First, I'm popping the next entry from the intermediate buffer.
And then I'm checking to see if I'm in the condition to split the data or not.
And remember that we have to do the split if the data already aligned plus the size of the data from this new item that we popped, it's bigger than the SIZE field from the Control register.
So if this condition is not true then we don't have to split the item.
And then I'm pushing in this data from this tx_item all the information from the buffer item.
And if I have enough information in this tx_item so the size is equal to the SIZE field then I know that I completed the alignment, I'm setting the end_time and I'm pushing this item in the tx_fifo.
On the else branch of this if, I'm in the condition in which I have to do the split.
So first I'm determining how many bytes I need in order to complete my tx_item.
So it will be number of bytes needed, it's equal to the SIZE register field minus the data size that we already have in this tx_tem.
Then I'm calling our split() function and then the splitted items I'm pushing back in the buffer but I'm pushing back first the second item and then the first item.
And this is because I want that in the next iteration from this while loop the first item which will be popped here to be this one.
The one which contains enough bytes so that the align logic will complete its item.
So it will go through this if here.
And that's all there is to this align logic.
So make sure that you understood the algorithm behind this logic.
Maybe you can try to put some messages here to see when the code is running to better understand what is happening.
Next, let's add this process_align pointer.
And we can add it here.
And let's kill it in the handle_reset() function.
And that's it.
Now the last thing that we have to add is this align_nb() function.
And we can take this code from this build_buffer_nb() and adapt it.
That's it.
And now let's take this function and call it in our handle_reset() function at the end.
So here, just like we did for the build_buffer(), we can start our align logic.
And that's it.
And now let's try to save and run and see if we get our align logic to push that align information in our tx_fifo.
Remember that in this test our Control register is configured with OFFSET = 1 and SIZE = 1 and we are pushing that 4 bytes of legal information so we should see 4 pushes in the tx_fifo.
So let's search for those messages.
And here it is.
Our push to RX FIFO is pushing 4 bytes of information, these ones, and then we have the messages from our align logic: TX FIFO push and this appears 4 times for each of the byte.
So FE here is this one, 60 is this one, B4 and 3B.
And if we continue to look in the log we can actually see that the RTL starts to output exactly the same bytes.
So we can see this message from our tx_agent.monitor saying that it detected byte FE which is this one from here.
Then the monitor detected on the output of the RTL this 60 which is this one and so on.
So it looks like we managed to implement correctly our logic to align the data.
That's it for this tutorial.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
