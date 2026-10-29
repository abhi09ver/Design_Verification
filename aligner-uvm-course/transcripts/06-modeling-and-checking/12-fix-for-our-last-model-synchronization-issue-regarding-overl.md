# Fix for our last model synchronization issue regarding overlapping interrupt

*Chapter: Modeling and checking · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to implement together the fix for our last model synchronization issue regarding overlapping interrupt requests.
This means that in our model component we are going to add or modify the API represented here with blue.
The starting point is the EDA Playground project called "Model Synchronization: Overlapping IRQs - Practice".
As always we have to copy this project.
And now let's resize the windows.
The first thing that we will add is this exp_irq field.
That's the declaration and now at reset let's set this field to value zero.
And that's it.
Next, let's fix the code in our setters for the interrupt requests.
Remember that we discussed in the previous tutorial that in these functions we no longer have to call that port to inform the scoreboard about the expected interrupt request but we only have to set with value 1 this new field that we added.
So let's do this.
And that's it.
Next, let's add this process pointer for our send task.
That's the declaration and now in handle_reset() we will have to kill this process.
And that's it.
Next, let's add this send_exp_irq() task.
That's it.
So the code is pretty simple.
We have our forever loop and at the negative edge of the clock, if the exp_irq is 1, then we send this information to the scoreboard and then we set to value 0 this field.
Next, let's add our non-blocking function for starting this task and remember that we have to call this non-blocking function as the last thing in handle_reset().
So that's our non-blocking function and now let's call this in handle_reset().
And that's it.
Now let's try to run to see if this update fixed our problem.
And remember that I'm using the same seed as I used in the previous tutorials.
So let's save and run this simulation.
Our simulation finished and let's see if we have any UVM error.
And no, this time the log is clean.
And let's search the log for that simulation time where we had the problem in the previous tutorial.
Remember it was time 3655.
So here our model is still generating two expected interrupt requests but because of our update to the scoreboard only one expected interrupt request is sent.
Now let's change in "Run Options" the seed to be random and now we can run the test a few times to see if we get any other UVM error.
The simulation finished and we don't have any errors, so this is good.
Let's try one more time.
It finished and now let's look in the log.
Again, we don't have any UVM error.
If we were in a real project this would be a good time to start to run this test in a regression.
And as I told you, in such a regression we can run this test something like 1000 times to see if we get any failures.
And if we get some failures from those regressions then we start to analyze those failures to see if we find any RTL issue.
Just keep in mind that even if you run a test with random seed a few times and that test is passing, it doesn't mean that it will pass with all the seeds.
This is why a regression is a very useful tool to have.
But before we close this tutorial, let's try to run one more time also with the waveforms enabled just to see how the simulation will look like on the waveforms.
The simulation finished and let's double check the log to see if it failed or not.
So no, it did not fail.
And now let's add on the waveforms the RX interface, the TX interface, and the interrupt request just to have an image of how these signals look like and to get a better feeling of what our environment is verifying.
So these are the signals on the boundary of our DUT, and now our environment is verifying everything, is verifying each of these interrupt request pulses.
On the RX interface is verifying the response returned by the RTL.
And on the TX interface is verifying all the transactions outputted by the RTL.
So this means the valid signal offset, size, and data.
So that's a pretty important milestone that we reached so far.
So congratulations for this!
That's it for this tutorial.
We managed to implement successfully our fix for our last model synchronization issue regarding the overlapping interrupt requests.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
