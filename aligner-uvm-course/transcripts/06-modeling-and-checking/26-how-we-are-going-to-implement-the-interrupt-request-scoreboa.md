# How we are going to implement the interrupt request scoreboard check

*Chapter: Modeling and checking · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about how we are going to implement the interrupt request scoreboard check.
This is the third and last check that we are going to implement in our scoreboard class and at this point we are quite familiar with the API that we need to add for such a check.
So let's go through the API that we need to add in our scoreboard class for this check and for the one which is similar to what we implemented so far we'll go quickly through it and we will focus more on the differences.
This is the API which is quite similar with the previous checks so let's go quickly through this one.
So we need to add a queue of expected interrupt requests and this will be of type bit.
Then we have our queue of process pointers.
Next we have our write() function to get the expected data from the model.
Then we have our watchdog task and finally the non-blocking function for starting this watchdog task and saving the process pointer in our process pointer queue.
So that's the API that we need to add in the scoreboard and as you can see it's quite similar to what we implemented for the previous checks.
However, one difference that we will have to keep in mind when we will implement this code it's related to the number of elements that we allow in our expected interrupt requests queue.
For the RX responses and TX items, we only allowed at most one item in these queues because of the nature of the MD protocol.
However, for the interrupt requests, our model is much faster than the RTL, so we should allow more items in this exp_irqs.
And my suggestion is to allow in this queue at most 5 elements.
Another class that we need to update with an API with which we are quite familiar is the environment configuration class.
In here, we will have to add a threshold for the interrupt requests just like we did for the previous checks.
And in the same fashion, we will initialize this threshold with value 10 in the constructor of the environment configuration class.
Now the main difference between this interrupt request check and the previous ones is that for the interrupt requests we don't have an agent which monitors the output of the DUT and sends that information to the scoreboard.
So we don't have a write_in_agent_irq() function like we did for the previous checks.
And this is because the output of the DUT, the interrupt request, is a simple wire which is active when it is 1.
So we can directly monitor that information in our scoreboard.
So we need a way to access that output from the DUT.
And for this what we can do is to add the interrupt request and the reset in our Aligner interface.
We can access this interface via its pointer from the environment configuration class and we have access to this environment configuration object in our scoreboard through this pointer.
This means that in our scoreboard we can implement a task which will monitor this interrupt request.
We can call this task rcv_irq() and in here we will have a forever loop which will look always on this interrupt request.
When the interrupt request is 1, the code from inside this task will be quite similar to what we implement for the write_in_agent() functions.
And just like before, we want to control the process of this task.
So this means that we will have to declare a process pointer and in order to allocate this process pointer we will have to declare a non-blocking function and we will call this function rcv_irq_nb().
That's it for this tutorial.
We talked about the API that we will need to add in order to implement the interrupt request check.
In the next tutorial, we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
