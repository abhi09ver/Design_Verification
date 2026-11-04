# MD monitor

*Chapter: MD agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to code together the MD monitor.
First we are going to code the item moon with these five fields, and then we are going to code the MD monitor.
By taking a lot of the functions and tasks from the app monitor and adapt it to our needs.
So let's get started.
The starting point is the MD monitor practice, which we have to copy.
Now let's resize the windows to make a little bit of room.
Now the first thing that we are going to code is the types file in which we need to add a type for the response.
So let's do this.
That's it.
Now let's include this file in our MD package.
That's it.
Now let's code the item mode.
And let's add the five fields we need here.
Prev item delay length data offset and response.
So let's do this.
That's it.
Now let's implement the convert to string function to print this information in a nice format.
To print the data.
Let's go to the item drive Master and take this code in which we build the data as a string.
And let's paste it here.
And now let's build the entire response of this function.
That's it.
Now the special thing here is to print the begin time and end time.
Now we have these two function get begin time, which is the getter for the begin time and also get.
End time, which is the getter.
Of course, for the end time and based on the result of the Isactive function, we either print an empty string for the end time, because at this point when isactive returns one get end time will return value minus one.
So we would have seen here a very big value if we would have printed get end time with the result minus one.
So this is why we did this check based on is active and when it's active returns one.
We simply print here an empty string.
Now let's include this file and see if everything compiles correctly.
Everything looks good.
Now let's code the MD monitor.
I did not specify in the diagram of the previous tutorial that the monitor should have the data width as a parameter, but we do need it in order to be able to access the interface.
Now let's include this file.
That's it.
And now before we code anything here in the monitor, let's create an instance of it in our MD agent.
That's it.
Now let's see if we did any compilation mistake with this code.
We did.
Let's fix it in the monitor.
We need to put here a semicolon and let's try again.
We have another error.
We still need to implement that handle reset function because we said that we are implementing this interface.
So let's also declare that one now.
So let's keep it empty and see if our code compiles.
Now everything looks good.
We don't have any compilation error.
Now let's go to our app package and try to get from there all the code for the monitor.
That's it.
So I align the code and I removed everything from collect transaction because this one will be unique for our MD monitor.
Now let's search for the APB and see where we have this word and replace it.
That's it.
Now one more thing that we need to do is to declare also here this virtual interface type.
That's it.
Now let's implement our collect transaction task.
While we are here, Let's not forget to connect this agent config pointer in the MD agent.
That's it.
Now let's continue with our collect transaction task.
At this point we need to wait for the beginning of the MD transaction.
And this is the place where we have to sample the signals one nanosecond after the rising edge of the clock.
And for this one, we said that in our MD agent config we need to declare that sample delay start transaction field.
So let's do this.
And let's create a getter and setter for that field.
That's it.
Now let's continue in our monitor.
So now let's wait that one nanosecond.
And also here we have to wait the positive edge and then wait one nanosecond.
And let's not forget also to increment the prev item delay value.
That's it.
So this is how we will detect the start of transaction, and we look on the valid signal every time, one nanosecond after the positive edge of the clock.
Now, at this point we know that our item started.
So let's sample all the signals which we can sample in the beginning of the item.
So this is the offset data and the size.
So this is that function that sets the begin time to the current simulation time.
And now we can call the output portrait function.
So after this, while we know that our item ended so we can collect the response information.
And this is the function that will set the end time value.
And now let's call our output port dot right.
And finally let's print the collected information.
That's it.
Now let's see if our code compiles and runs correctly.
The simulation finished.
We have no compilation error.
And let's see what our monitor printed.
So first we wanted to drive this a0 c0 with offset two and our monitor collected correctly the information a0 c0 with offset two and response okay, and noticed that the begin time is 116 nanoseconds and the end time is 125 nanoseconds.
And let's try to also run with the waveforms and see where this is on the waveforms.
Let's add the MD signals.
Now let's zoom at the first item.
And you can see that the rising edge of the clock is at 115 nanoseconds.
But because we waited one nanosecond extra in order to sample the valid a little bit later.
Our start time is 116 and the item ends at 125, which is the next rising edge of the clock.
Let's quickly check the other items.
Let's take the third one for example.
So it started at 216, ended at 225.
It collected three four, two, nine is the same that we want it to drive.
The offset is one, the size is two.
So our RTL should have returned an error response, which is this one.
And let's also see this on the waveform.
The third item, which is this one had a response of error.
So everything looks good.
Our monitor logic works correctly.
That's it for this tutorial.
Thanks for watching and see you in the next tutorial.
