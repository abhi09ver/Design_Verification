# Coverage related to the MD protocol

*Chapter: MD agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to code together the coverage related to the MD protocol.
This is the verification plan that we discussed in the previous tutorial, and we are going to implement the coverage with the information coming from the item.
And also we are going to implement the coverage related to reset.
We want to see if there was an access ongoing when a reset became active.
The starting point is the MD Coverage Practice project, which we need to copy and select open epi wave.
After run, resize the windows and first let's create our CFS MD coverage file.
Let's include this file in our MD package.
Now let's copy from our APB package the coverage Average implementation, as that one will be quite similar to what we will have to implement for the MD protocol.
So we need to copy everything starting with this declaration of the analysis, implementation, port and all the way to the end of the coverage class.
And now let's copy paste this here in our MD coverage file.
And let's start adapting the code to our needs.
Let's keep this cover index wrapper base and cover index wrapper.
Because we also need to cover the data bus of the MD protocol.
And for this we only need to replace the name APB with the name MD.
Now for the coverage class.
Let's rename this to MD and also add the data width as a parameter for this class.
Let's fix the type of the agent config pointer.
Now for this wrapper instances we only need to keep two for the data.
And let's replace the name APB with the name MD and also use here the parameter data width.
Inside this cover group we need to replace these items with the information coming from the MD monitor.
So remember that the offset goes from zero to data within bytes minus one.
And let's do something similar for the size.
But the size will go from one to data within bytes.
Response is the same and the length will mostly be the same.
We only need to change a little bit the bins, and for the information coming from the MD monitor, the illegal value for the length will be zero.
And we want to cover the bins starting with value one.
Previous item delay will be the same and instead of this cross we need to define a new cross between the offset and size.
And for this one, we need to ignore the combinations between offset and size, for which offset plus size is bigger than the data within bytes.
We can get rid of this transition for the reset.
We only need to change this pixel to valid.
And for the instances of this wrap cover class, we need to only keep two for the data.
Here in the right item, we need to adapt the sampling logic for the data.
And here we need to sample the index of the data bus.
So we need to compute that index based on the offset the byte index and the bit index.
So let's do this.
That's it.
And we can get rid of this for loop here.
Here in the reset we only need to change the name here to MD and cover the valid.
And we also need to declare this type here in the coverage.
So let's copy it from the monitor.
That's it.
Now we also need to fix the coverage to string function.
And let's align the code.
That's it for this part.
Here we only need to change from APB to MD.
And that's it.
Now let's search for the APB name just to make sure that we replaced it everywhere.
We still have it here.
That's it.
And finally what we can do in the MD coverage is to print the coverage information.
But let's not print it here after every collected item.
But let's print it at the end of the test.
And we can use the report phase part of the UVM.
So this message will be printed at the end of the test, and we will get two prints for this one, one from the ethics agent and one from the tax agent.
Now finally, let's go to our Cfmd agent and create the instance of the coverage.
And also we should connect the pointers, the agent config pointer and the analysis implementation port of the coverage.
And we should create the instance of the coverage based on the has coverage field from the agent config.
And finally let's connect the pointer of the agent config and also the port.
That's it.
Let's save and see if our code compiles and runs correctly, and we should look on the information printed at the end of the test.
Our simulation finished and let's see what information we got from our coverage class.
So this is the information from the tax agent.
And we can notice that for the offset and size we cover these ones only 25%.
And this is because the RTL will only output one combination of offset and size based on what it was configured.
And let's see for the Eric's agent what information we covered.
So the overall coverage for the item is 26%.
And again we have this offset and size each with 25%.
And this is because we constrained our tests in here in test random in some previous tutorial to only drive accesses with the maximum number of bytes, and this was because we wanted to fill the internal Fifo.
But now we can get rid of those constraints.
And let's try again to see if we can increase the coverage, at least on the air interface to go above this 26%.
Okay.
Let's see now what figures we have for the coverage.
And you can see the coverage jumped to 72% by removing those constraints.
But if you look closely, the size is still 75%.
So apparently we did not drove all the possible values for the size.
And let's try to open the EP wave after run to see exactly what size was not covered.
And one other thing that we can do is to go to the item mode in the convert to string function, and also print here the size because we are only printing now the data, but it would be good to try to search in the log for size.
That's it.
Now let's try to run to see exactly which value of the size was not covered.
Let's load the waveforms for the ADX and takes interface.
And now let's try to look on the ADX interface.
So we have size 1123232.
So it looks like size four is missing.
And let's also try to search after size four in our log.
So we have this message here and search for size four which is not present.
And we can easily fix this by going in our test random and increase the number of items that we send in our test from 11 to, let's say, 100.
And let's try to run again to see how the waveforms look like in this scenario.
And if the coverage for the Addicks interface jumps to something bigger than this 72%, that's it.
Our simulation finished and it looks like we are driving a lot of items on this waveforms.
And let's look on the coverage figures to see if our coverage improved.
And now for the Addicks part.
The cover item went up to 84%.
And we also covered all the values of the size.
That's it.
For this tutorial we managed to implement the coverage for our MD agent.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
