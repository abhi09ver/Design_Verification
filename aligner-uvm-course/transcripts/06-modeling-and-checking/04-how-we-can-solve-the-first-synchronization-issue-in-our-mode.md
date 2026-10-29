# How we can solve the first synchronization issue in our model regarding the

*Chapter: Modeling and checking · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about how we can solve the first synchronization issue in our model regarding the FIFO flags.
In our model, we have two FIFOs for the RX and for the TX and for both of these FIFOs we have two processes push process and pop process and these processes, or threads, are running independent of each other.
And this is a problem for us because it means that we cannot identify the scenario in which there is a push and a pop in the same simulation time.
If we are looking only on the RX FIFO our push process is responsible for updating the RX_FIFO_FULL flag.
And the stack trace let's say for the RX_FIFO_FULL function which is updating that flag looks like this.
On the other side, the pop process is responsible for updating the RX_FIFO_EMPTY flag.
And again, the stack trace for this function set_rx_fifo_empty() looks like this.
In order to solve this synchronization issue, we need to do several things.
First, we need to somehow make aware this push_to_rx_fifo() task of this set_rx_fifo_empty() and in particular, we want to have the following logic: if the push_to_rx_fifo() task is called in the same simulation time as this set_rx_fifo_empty(), we want to somehow cancel the effect of this set_rx_fifo_empty().
So, in other words, there is no empty flag set when we want to do a push in the FIFO.
In the same way, on the other side, we don't want to set the FIFO full flag when the pop task is called in the same simulation time.
So, we want to create this dependency between the push task and set_rx_fifo_empty() function and on the other side between the pop task and set_rx_fifo_full() function.
So let's see how we can create the dependency between the push task and set_fifo_empty() function and then we can apply the same technique on the other side for pop and set_fifo_full() function and of course it will be the same for the TX FIFO.
So let's see the implementation of these two methods.
In our push_to_rx_fifo() task the code is pretty simple.
We are just putting new information in our RX FIFO model and then we call this inc_rx_lvl() function.
And in our set_rx_fifo_empty() function, we are doing this predict() with value 1 on this RX_FIFO_EMPTY register field.
And then if the interrupt is enabled, we inform the scoreboard to wait for this interrupt.
One way in which we can create this dependency is by using process pointers and let me show you how we can accomplish this.
First, what we want to do is to delay the effect of this set_rx_fifo_empty() function by a small amount of time.
This means that we have to update this function in the following way.
We put inside this set function a fork-join_none so that we can start a process.
Inside this process, we delay the initial code which is this one by a very small amount of time.
In our case, let's consider this to be something like 2 time units.
I'm using here this function for waiting an NBA region but you can simply think about this like 2 time units, regardless of what this time unit means.
The other important aspect of this code is that we save the pointer to this process in this field here.
On the other side, on this push_to_rx_fifo() task, we update this task with this line.
We simply call this function kill_set_rx_fifo_empty() which is killing this process from here.
And the implementation of this kill function is this one.
Again, we have a fork-join_none in which we wait only one time unit, in our case one NBA region, and then we kill this process from here.
And let's see what's the effect of this change when there is a push and pop in the same simulation time.
Because these threads are running in parallel, we can't say which of these ones are executed first.
So, let's consider both possibilities.
First, let's consider that this pop task is happening first and then this push_to_rx_fifo().
Remember, this will happen in the same simulation time.
So, if this pop is executed first by the simulator, when this set_rx_fifo_empty() function is called, this process is started in parallel, so this one will wait for two time units and then it will set this RX_FIFO_EMPTY flag.
But before this code is executed, the simulator will also process this push_to_rx_fifo() task.
And in here, we are calling this kill_set_rx_fifo_empty().
This function will wait for one time unit and then will kill this process_set_rx_fifo_empty.
So, at this point, one time unit passed and in here we did the first iteration in this repeat.
So when the simulator will try to execute this line, the repeat will still have one more iteration to go.
So this means that this RX_FIFO_EMPTY it's not yet set and this process is terminated.
If we are, however, in the other scenario in which the simulator will first execute this push_to_rx_fifo() and then this pop task again in the same simulation time, let's see exactly what will happen in this scenario.
So, first, this kill_set_rx_fifo_empty() function is called.
So, this process is started.
And if we were to directly call this kill_process() for killing this process without waiting this time unit then at this point this process would have been null.
So, this is why it's important to wait for this one time unit.
On the other side, this set_rx_fifo_empty() function is started after the call to this kill_set_rx_fifo_empty() so this process is allocated and started here.
And after one time unit the process is killed.
So, this is how we solve this problem.
Every time we call this push_to_rx_fifo() if in the same simulation time this set_rx_fifo_empty() function is called then its process will be terminated.
So in this way if there is a push and a pop in the same simulation time we will never set this RX_FIFO_EMPTY.
Now one other important aspect here that I want to mention is the time unit that I am using here.
In our case I'm using this wait for NBA region task.
And this works ok if these two processes, the push process and the pop process are working on the same clock.
And in our case, we do have the same clock used for the push and pop process.
But if we were to have different clocks, independent clocks for these push and pop processes, then there is a good chance that this wait for NBA region would not work.
And in such a case, you can actually replace this wait for NBA region with something like wait 1 picosecond or any other time unit but keep in mind that it must be less than the clock period.
And regardless of the time that you are using here for waiting, what's important is that the waiting period from this set function is greater than the waiting period from here.
We can apply the same technique for the other three scenarios that we have, so the relation between the pop and this set_rx_fifo_full() and the same thing repeated for the TX FIFO.
But there is no meaning to go right now through all these three cases.
We will do this when we will implement this in the code.
And let's quickly see what API we need to add in our model component in order to implement the fix for this synchronization issue.
So first we need to add the process pointers for the processes from our set functions.
Then we need to add the kill functions in order to kill these processes.
So these are the new things that we need to add, but we also have to update some of the code.
So we need to update the functions which are setting the flags and then we also need to update the push and pop tasks.
That's it for this tutorial.
We talked about how we can fix the FIFO flags updates when we have a push and a pop in the same simulation time.
In the next tutorial, we will implement all this together in the code for all four FIFO flags.
Thanks for watching and see you in the next tutorial.
Bye!
