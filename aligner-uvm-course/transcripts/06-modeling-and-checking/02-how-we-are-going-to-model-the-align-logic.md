# How we are going to model the align logic

*Chapter: Modeling and checking · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about how we are going to model the align logic.
This is the block diagram of our model component with the API that we implemented so far and in this tutorial we are going to focus on this part of the model.
So in this align logic we are going to implement the algorithm for popping data out of the intermediate buffer, align it and then push it to the TX FIFO.
And to better understand what we need to implement let's see a short animation of the behavior of our RTL in this scenario.
As usual, this is the block diagram of our Aligner RTL and above we have the three relevant registers: the Status register, Interrupt Requests register, and Control register.
For the align logic we are going to model two register fields: the TX_LVL and TX_FIFO_FULL.
And to understand this align logic let's continue from where we left off in a previous tutorial in which we had in the intermediate buffer 3 entries.
And the sum of bytes in these 3 entries is 7.
And as initial values for the registers we have at this point TX_LVL = 0, TX_FIFO_FULL = 0 and in the Control register we have the OFFSET equal to 0 and SIZE equal to 4.
So in this scenario the align logic will have to align 4 bytes from offset 0 and once it does that it will have to push that information in the TX FIFO.
The align logic will start its job once it sees in the intermediate buffer that it has enough bytes to align, in our case 4.
And because in this scenario there are at least 4 bytes in the intermediate buffer then the align logic can start aligning the data.
So it will take the first byte and put it on offset 0, then it will pop the next entry which has 2 bytes and put it here.
Now the align logic only needs one more byte to complete its 4 bytes of data, but the next entry in the intermediate buffer has 4 bytes.
So the align logic will have to be able to split this information and take only the first byte, put it here, and it will have to leave in the intermediate buffer the rest of the bytes, these 3 ones here.
But once it has these 4 bytes aligned then it will have to push this information in the TX FIFO.
So at this point the TX_LVL will be incremented to 1.
Now in the intermediate buffer there are only 3 bytes so the align logic cannot align these bytes it will have to wait for at least one more byte to enter in the intermediate buffer.
And when this is happening then there are 4 bytes here so there are enough bytes for the align logic to work with so it will start aligning this information.
And once this is done it will also push this information in the TX FIFO.
Now the TX_LVL can be incremented to value 2.
And now let's advance quickly up to the level where the TX FIFO becomes full.
So let's assume that everything comes aligned and it will go directly in the TX FIFO.
So at this point the TX_LVL is 8, so the FIFO is full.
So this means that the TX_FIFO_FULL flag will have to become 1.
And at this point, if we receive enough bytes in the intermediate buffer, the align logic will align these bytes, but it will not manage to push them in the TX FIFO as the FIFO is already full.
And just like for the RX FIFO, we will model this waiting period until the FIFO becomes not full using that uvm_tlm_fifo class.
And now let's see what API we need to add in our model component.
So obviously, the first thing that we will have to add is the model of the TX FIFO.
And as before, we will model this TX FIFO using this uvm_tlm_fifo class.
And remember that the main reason for which we are using this class is that it has those put() and get() tasks which are waiting if the FIFO is either full or empty, so we don't have to model that waiting period.
Next, we will have to implement a function called set_tx_fifo_full() which will set to 1 this TX_FIFO_FULL flag from the Interrupt Requests register.
Next, we will have to implement this inc_tx_lvl() function which increments this TX_LVL register field.
Then we will implement this push_to_tx_fifo() task which will push in our TX FIFO model.
So these three functions and task will be quite similar to what we implemented for the RX FIFO.
The next function that we will have to implement is this split() function.
Remember from the previous animation that the aligned logic should be able to split an entry from the intermediate buffer in order to use only the bytes necessary to complete the currently aligned data.
And for this we need to implement this split() function with three input arguments.
The first one, number of bytes, represents the point at which we want to split an item. and the function receives that item in its second argument, in this one.
So if you remember the previous animation this item will be that 4 bytes of data that we had in the intermediate buffer and if we set this num_bytes to value 1 then it will split this item into two items.
The first one with size 1 and the second one with size 3 and the result will be placed in this last argument here.
We must pay attention when we implement this split() function as we have to check the validity of this num_bytes value.
First of all, it cannot be 0 and also it cannot be equal to the size of the item that we received.
So, if this num_bytes is equal to 4 and we receive a 4 bytes item, we cannot split this item by 4.
These num_bytes will have to be smaller than the size in this item.
The next task that we will have to implement is this align() task.
So this is the main task which will align that information.
And because this align logic will have to try to align information every time, this means that we will have to implement in this align() task a forever loop.
In this forever loop, we will look in the intermediate buffer to see when there are enough bytes to align.
And when this happens, this align() task will align that information and it will try to push that information in the TX FIFO.
And just like before, we want to control the process of this task and for this, we will declare a process pointer called process_align and to allocate this pointer and to start the align task we will have to declare a function called align_nb().
And these are all the new things that we need to add in our model component in order to implement this align logic.
That's it for this tutorial.
We talked about the new API that we have to add in our model component in order to implement this align logic.
In the next tutorial, we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
