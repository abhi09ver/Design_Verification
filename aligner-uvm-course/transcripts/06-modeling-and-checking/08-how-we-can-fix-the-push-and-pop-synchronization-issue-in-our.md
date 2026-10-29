# How we can fix the push and pop synchronization issue in our model

*Chapter: Modeling and checking · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about how we can fix the push and pop synchronization issue in our model.
First, let's go through a short example to better understand why there is an issue with our push and pop actions from our model.
We have here the block diagram of our model and here the block diagram of our RTL.
And for our example, let's consider that the Control register is configured in this way: SIZE equal to 1 and OFFSET equal to 0.
And let's see what's happening in these two entities when we are driving three MD RX transactions with maximum size 4 bytes.
In the first clock cycle of our example, in the RTL, the first MD RX transaction will end up in the RX Controller.
However, in our model, this first MD RX transaction will first end up in the RX FIFO and then our buffer builder will take this entry and put it in the intermediate buffer.
In the second clock cycle, in the RTL, this entry will end up in the RX FIFO and the next one will be taken into this RX controller.
But in our model, in this second clock cycle, the align logic will take this entry from the intermediate buffer, then it will split this entry to push each byte in the TX FIFO.
Then, the TX Controller will pop one entry from the TX FIFO.
Also in this second clock cycle, as everything is happening in parallel, the second MD transaction will end up in the RX FIFO.
In the third clock cycle, in the RTL, this entry from the RX FIFO will end up in the Controller.
The Controller will start to split this entry and it will push the first byte in the TX FIFO.
In the same time, this entry from the RX Controller will end up in the RX FIFO and the third MD RX transaction will end up in the RX Controller.
In our model, however, the buffer builder will take this entry from the RX FIFO and it will end up in the intermediate buffer.
Then the align logic will take this entry, split it, and put the bytes in the TX FIFO.
In the same time, the third MD RX transaction will end up in the RX FIFO.
In the fourth clock cycle, in the RTL, this entry from the TX FIFO will end up in the TX Controller.
So, at this point, the RTL will start to drive this information on the MD TX interface.
Also, in the same time, the second byte from the Controller will be pushed in the TX FIFO and finally, the RX Controller will push this information in the RX FIFO.
In our model, however, the buffer builder will take this entry from the RX FIFO and then the align logic will start to process this information and it will push only one byte in the TX FIFO.
So, as you can see, after only four clock cycles, there is a massive difference in the way the information is distributed in these two entities.
In our model, the TX FIFO is full, the RX FIFO is empty, and in the RTL the TX FIFO has only one entry and the RX FIFO has two entries inside.
This big difference in the way the information is distributed in our two entities does not really affect the expected output data.
In the end, our model will be able to predict the expected data on the TX interface correctly, and we can use that information to check the output of the DUT.
However, the interrupt requests do depend on the way the data is distributed, so four of our five (interrupt) requests reflect the way the information stays in these FIFOs in the RX and in the TX.
And in this simple scenario that we looked over, for example in the TX FIFO, our model is already full, so it might generate an expected TX_FIFO_FULL interrupt while the RTL has only one entry in the TX FIFO.
And even if we simulate more clock cycles, the RTL might never end up with a full TX FIFO if the MD TX agent will pop information fast enough.
So in order to predict the expected interrupt requests, we need to update our model so that the information is distributed correctly in the RX and TX FIFOs.
And let's see what options we have in order to implement this fix.
One of the first thing that the verification engineers will try to do in such a scenario is to try to add delays in the model.
For example, in the push_to_tx_fifo() task, one might try to add delays like these ones.
From my experience, trying to add such delays will end up in a synchronization nightmare.
In most scenarios these delays are not static but they depend on some internal state of the RTL and taking this approach will end up with a really complicated model in which you have strange conditions to wait for different number of clock cycles for different scenarios.
So my recommendation to you is to try to avoid as much as possible adding such delays in your model.
Another approach that you will see in real life for fixing this synchronization issue is to try to copy the RTL code.
And this is definitely a road that you should never take when you are doing verification.
When you are copying the RTL, you are no longer doing verification as you are copying the entity that you are trying to verify.
So my advice to you is to never try to copy the RTL code in order to solve some synchronization issue that you have in your environment.
A third alternative is to try to probe inside the RTL and see when the RTL is doing the push and pop in its FIFOs.
But this approach comes with a warning: you should not try to blindly trust the RTL with these push and pop actions, but you should only take that information just as a hint.
And let's see how we can accomplish this on the push to RX FIFO action and then we can take the same approach in the other three cases.
So, currently, in our environment, we have this push_to_rx_fifo() task when we try to push some information in our RX FIFO model.
And what we can do is to change this task a little bit and add this synchronization task here.
So let's see how we can implement this synchronization task.
The easiest implementation would be this one.
In our virtual interface, we would have this rx_fifo_push signal which is probing inside the RTL at this point and when that signal is 1, our task is finished.
But this means that we will rely on the RTL to tell us when to push in the RX FIFO and this is something that you should not do as you will rely on the information from the DUT which you try to verify.
So, a different approach would be to change this code in the following manner: In a fork-join_any construct, we can have two branches.
On the first branch, we can wait for the RTL to push in its RX FIFO.
But on the other branch, we wait for a given number of clock cycles, in this case let's say 10.
This means that we wait for the RTL to push in its RX FIFO for a maximum of 10 clock cycles.
If this is not happening, then we exit this fork-join_any and we proceed with our code from this push_to_rx_fifo() task.
And to help us with debug, if after 10 clock cycles the RTL did not push in its RX FIFO, we can generate a warning.
You can make your environment more aggressive and generate here an UVM error as there is a good chance that if you end up on this line, something is wrong in the RTL.
However, there is still a problem with this code because it does not take into consideration if the push can actually happen.
And this depends on the state of the RX FIFO.
If the FIFO is full, then the push will not happen.
And until now, in our environment, this issue was taken care of by our model of the RX FIFO.
The put() task is waiting until there is room in the RX FIFO to put this information.
So, if we are blindly waiting for these 10 clock cycles even if the RX FIFO is full, then we will incorrectly trigger this warning.
We can easily fix this problem by changing the code in this repeat loop in this manner.
We can advance through this loop only if the RX FIFO is not full.
So with this update our synchronization task will wait for the RTL to do the push in its RX FIFO for a maximum of 10 clock cycles in which the RX FIFO is not full.
If these 10 clock cycles are reached and the RTL did not push in the RX FIFO, then our code from the push_to_rx_fifo() task will continue.
So, in this way, we are not relying only on the RTL to do its push in the RX FIFO, we have this alternative.
And if this is happening, we are moving forward with our push to RX FIFO action.
So, that's the strategy that we can apply to the other three synchronization tasks, the only difference will be the condition in which we advance through this repeat loop.
And let's see exactly what should be the conditions in each case.
So for the RX FIFO push, we already talked about this.
We need to look if the RX FIFO is not full.
On the other side, on the RX pop we need to look if the RX FIFO is not empty but also if the TX FIFO is not full.
We need this second condition in order to be sure that some of the information which we popped out of the RX FIFO has room in the TX FIFO.
For the push to TX FIFO we need to look if the TX FIFO is not full and finally for the TX FIFO pop we need to look if the TX FIFO is not empty.
There is one difference in this last scenario, the repeat will have to be much longer than in the other synchronization tasks and this is because the actual moment when the pop is done from the TX FIFO depends on the randomization from our MD TX agent.
So the pop will happen when the MD TX transaction ends and for this reason the number of loops in that repeat will need to be much bigger to cover all the random ranges that we can generate.
Now let's go through the things that we need to add in our environment in order to implement this.
First, in our interface, we need to add the signals with which we are going to probe the internal signals from the RTL.
Once we have these signals, we need to assign them in our testbench module.
So for each of these 4 signals, we will do an AND between the valid and the ready for each of the FIFO action.
So, if we look at the first signal rx_fifo_push, this one will be 1 when inside the RTL in the RX FIFO push_valid and push_ready are both 1.
So that is the moment when the push is happening inside the RTL.
And we are applying the same logic for the other 3 signals.
Once we have that, we can add in our model component the four synchronization tasks.
And then we can use these tasks to update our push and pop tasks.
That's it for this tutorial.
We talked about how we can fix our synchronization issue regarding the push and pop actions.
In the next tutorial, we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
