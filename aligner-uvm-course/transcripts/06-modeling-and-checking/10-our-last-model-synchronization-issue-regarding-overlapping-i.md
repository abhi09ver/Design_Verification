# Our last model synchronization issue regarding overlapping interrupt requests

*Chapter: Modeling and checking · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about our last model synchronization issue regarding overlapping interrupt requests.
In the previous tutorial, we saw that there is a problem with our model when there is a scenario in which an interrupt request is generated due to two or more reasons.
In that particular case, the interrupt request was generated due to RX FIFO empty and TX FIFO empty.
This behavior is also described in the Aligner specifications.
The RTL is implementing this OR gate, so from this point of view, this is not a synchronization issue but a modeling issue.
We need to implement in our model this OR gate behavior.
However, when we looked in the log, we saw that our model was generating these two messages to tell us that it is generating expected interrupt requests for both of these reasons: RX FIFO empty and TX FIFO empty, both at the same simulation time.
From the environment point of view, this is a synchronization issue because all the expected interrupt requests are generated from parallel threads.
And let's see the stack traces of all the threads from which our expected interrupt requests are generated.
On the thread of this write() function we are calling this set_max_drop() which is setting the MAX_DROP interrupt request.
However, for the other four interrupt requests we are starting parallel threads from these non-blocking functions.
So the problem is that these five threads are sending in parallel to the scoreboard the expected information, but what we need to do is to implement an OR function between all these expected interrupt requests.
There are many solutions to this problem and one way in which we can fix this issue is the following: instead of immediately sending to the scoreboard the expected interrupt request, what we can do is to save this information into a local field of the model for just a short period of time.
This approach is actually implementing indirectly the OR gate.
If two or more of these parallel threads are setting in the same time this exp_irq with value 1, then this is equivalent with an OR gate.
But now we have to implement a logic which will send this expected information to the scoreboard.
And to accomplish this, we can create a task called send_exp_irq() which we can start in parallel as a separate thread.
The implementation of this task is pretty simple.
We know that all these five threads will set this exp_irq to value 1 always at the positive edge of the clock.
So this means that our task will have to wait for all these threads to have the possibility to set this value to 1.
So based on this we can have the following implementation for this task.
In a forever loop, we can wait for the negative edge of the clock.
And at this point, if the exp_irq is already set to 1, then we send this information to the scoreboard and reset back to 0 this exp_irq.
In this way, at the positive edge of the clock, all these threads can set this variable to 1, and then at the negative edge of the clock, we send this information to the scoreboard.
And now let's see how we should update our model component in order to implement all these.
First, we need to add our exp_irq field.
Next, we will have to add the process associated with this send task.
After that, we will have to declare this send_exp_irq() task.
And to start this task, we will have to declare this non-blocking function.
So these are the new things that we will have to add in our model but we also need to update some of the functions from here.
So first we will have to update our set functions for setting the interrupt requests.
The change that we have to do here is pretty simple.
Instead of calling that port_out_irq we need to set this exp_irq to value 1.
I added here the code only for the set_max_drop() but the same thing we will have to implement in all the functions.
The other thing that we will have to update in our model component is the handle_reset() function.
In here we will have to kill this process associated with our send task. will have to reset this exp_irq to value 0 and also we will have to start our send task.
That's it for this tutorial.
We talked about what we have to do in order to fix our synchronization or modeling issue for overlapping interrupt requests.
In the next tutorial we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
