# RX response scoreboard check

*Chapter: Modeling and checking · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to implement together the RX response scoreboard check.
This means that we are going to add in our scoreboard class the API represented here with blue and also in the environment config class we need to add this field with the getter and the setter.
The starting point is the EDA Playground project called "Scoreboard Check: RX Response - Practice" which we need to copy.
Now let's resize the windows.
The first thing that we will add is this queue of expected RX responses.
So let's go to our scoreboard class and below the port declaration let's add this queue.
That's the declaration and now in our handle_reset() function let's clear this queue.
And that's it.
Next, let's add this queue of process pointers.
And that's it.
Next, let's add this function which will help us to kill all the processes from a queue.
That's it.
The implementation is pretty simple.
It's important here to get the queue of processes as a reference and then in a while loop, while the size of this queue is greater than zero, we call the kill() function of the first element in this queue and then we pop out of the queue this element.
Now that we have this function, let's use it in our handle_reset() to kill all the processes saved in this queue here.
And that's it.
Next, let's add in our environment configuration class this threshold field with the getter and the setter.
And remember that we need to initialize this threshold field with value 10 in the constructor of the class.
Here I declare the field and in the constructor I initialize it with value 10 and now let's declare the getter and the setter for this field.
And that's it.
Next, let's add this task exp_rx_response_watchdog().
Remember that we will start this task every time we push a new entry in this exp_rx_responses queue and in this task we will trigger an error after a given number of clock cycles and that number of clock cycles is determined by this threshold field from the environment configuration class.
So let's do this.
That's it.
The implementation is pretty straightforward.
We simply wait for this many clock cycles and after that we trigger this error.
And we stop this error from being triggered by killing the process of this task when the RTL also sends to the scoreboard the RX response.
Next, let's implement a function which will start this watchdog task.
So we will implement this exp_rx_response_watchdog_nb().
That's it.
So we have our fork join none and in here we take the pointer to the process, we push it into our queue, we start our watchdog task and at the end of the task we make sure that our queue of processes is not empty as this will suggest an implementation error and then we pop the first entry from our queue.
Next, let's implement our write_in_model_rx().
So this is the logic which must be triggered every time our model sends to the scoreboard the expected RX response.
That's it.
So, the first thing that we have to do is to check the size of this exp_rx_responses queue.
Remember that we cannot have more than one entries in this queue as the MD protocol does not allow for overlapping transactions.
So, this is why we must check the size of this queue as otherwise something might be really wrong with our code.
And then we push this expected response in our queue.
And then we start our watchdog task.
The last function that we need to implement is this write_in_agent_rx().
So in here we will have to kill the process of the watchdog task and compare the received response with the expected response.
So let's do this.
That's it.
So with this if we make sure that we are at the end of the item via this is_active() function and then we get the next expected response from our queue.
After that we kill the process of that watchdog task.
So with this line we prevent the check from here to be triggered by killing this task.
And then we pop that process pointer from the queue and finally we compare the expected response with the received response.
Now let's try to run our simulation to see if we get any errors with our code.
The simulation finished and if we look through the log we don't get any UVM error or fatal error so everything looks good.
And now let's try to introduce an error in our code in order to trigger this error to see that everything works okay.
So let's go in our model and let's try to change the expected response that the model will send to our scoreboard.
And we can introduce an error here.
We can change the expected response at this point sent by the model to the scoreboard.
We can change it to error and in this way we will trigger the error from the scoreboard saying that the expected response is not equal to the received response.
So let's give it a try.
That's it, the simulation finished and let's see if we get our error in the log and here it is.
Mismatch detected on the RX response.
The expected value it's error and the received it's OK.
So it looks like our check is working correctly and now let's not forget to fix this code here and put OK response.
And if we try one more time we should not get any errors.
The simulation finished and let's look through the log.
No, we don't get any errors so everything ran OK.
That's it for this tutorial.
We managed to implement correctly our RX response scoreboard check.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
