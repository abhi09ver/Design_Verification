# Register field callback

*Chapter: Register model (RAL) · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to code together the register field callback.
The starting point is the project "Register Field Callback - Practice" from EDA Playground which we need to copy.
And now let's resize the windows.
Before we code our register field callback, let's first modify our register access test so that we have a scenario in which we can see that drop count increment and then we can clear that drop count.
So what we need to do in our register access test is take this part of the code and put it first here.
So this one is driving two accesses on the MD RX interface and we want to make these accesses illegal so we can change the size to be equal to 3.
So both of these accesses will generate illegal transfers on the MD interface.
And we can get rid of this code.
And after we drive these illegal accesses, let's read the Status register.
That's it and now let's give it a try to see how the waveforms look like in this case and let's select also "Open EPWave after run".
The simulation finished and now let's add on the waveforms the MD RX signals.
And let's see what is happening on the waveforms.
So we have two accesses, both with size 3 and both are returning an error as they are illegal accesses.
Now we can put on the waveforms the drop counter from the RTL to see if the RTL is incrementing that counter every time there is an illegal access.
And we can get that drop counter by going to "Get Signals" and then to this "regs" module and if we scroll down, there is this "status drop count", so let's add this one on the waveforms.
So the RTL increments this drop count after every illegal access.
And now let's also add on the waveforms the APB interface.
Here we have our read access from the Status register, so with address 0xC and the RTL returns value 2 which is the value of this drop count from here.
And if we look on the log we should get an error.
So we have this error here where the environment says that there is a mismatch in the read value of the Status register because the RTL returned 2 so this corresponds to the drop count but the environment was expecting 0 in this drop count.
And this is because in the environment we are not currently modeling this scenario in which we can increment the drop count.
This we will implement later when we will code the model.
But for now, just to make this test work, let's call the predict() function here for the drop count to set value 2 in our drop count.
And I just want to point out that this is something that you should not do in a real project, so you should not call the predict() function of a register field from the test.
This is the job of the model.
But we are doing this now temporary just to be able to see the effect of our callback on the CLR register field.
That's it.
I also put here a comment: "Don't do this in a real project", because, again, calling the predict() function from the test is completely wrong.
We are doing this just to be able to see the effect of our callback on the CLR register field.
Now let's try to run again our simulation to see if we got rid of the UVM error saying that there is a mismatch for the drop count.
That's it.
We can also see on the waveforms that the simulation went beyond the moment when the read value was returned from the Status register.
And now let's also look on the log to see if we get any error.
So no, we don't get any UVM error.
So now that our environment is aligned with the RTL on this drop count, let's try to clear our drop count register.
And we can do this by writing 1 in that CLR register field from the Control register.
So let's try to do this.
That's it.
So I'm setting 1 in the desired value of the CLR register field and then I'm calling the update() task.
So let's see the waveforms of this simulation.
OK, so we have our two illegal accesses, then the read from the Status register and then the clear action on the drop count.
So this 1 from here corresponds to the CLR register field and you can also see that the RTL cleared its drop count.
So now if we add a read here again from the Status register, we should get a new mismatch.
And this is because our environment still thinks that in drop counter it should have value 2 but the RTL already cleared its drop count here because of the write to the CLR register field.
So let's try to do this.
That's it and now let's run again.
So you can see on the waveforms that when the Status register is read again, the RTL returned value 0 as its drop count was cleared here.
But if we look on the log, we should get an UVM error saying that there is a mismatch on the Status register.
RTL returned 0 but we are still expecting value 2 because we have 2 in the mirrored value of the drop count and that 2 was set here.
So this is scenario in which we can test our register field callback.
So our callback should also clear the mirrored value of the drop count when this write to the CLR register field is detected.
So first let's declare our "clear count drop" file... and now let's include this one in our Aligner package... and now let's declare our callback class.
So, in here I declared a pointer to this CNT_DROP so we have access to it when we try to predict it with value 0.
And here in the post_predict() let's identify a write with value 1 in our CLR register field.
That's it.
So after there is a write with value 1 I'm clearing here the drop count and after that I'm setting back to 0 the value of the CLR register field.
And also I'm printing this message so if everything is OK when we run our simulation we should see this message printed.
And now let's go to our model and in the connect_phase() let's add this callback to our register field.
So here let's first create an instance of this "clear count drop".
And now let's connect that CNT_DROP pointer.
And now let's add the callback using that add() function from uvm_callbacks class.
That's it, so I'm adding this callback instance to our CLR register field instance.
Now let's try to run and see if this code will clear our mirrored value from the CNT_DROP register field.
The simulation finished and from the waveforms we can see that the simulation did not finish when the read data was returned from this read from the Status so that's a good sign.
This means that we do not have here an UVM error and let's also look on the log.
So we don't have any UVM errors and we should also see our message for clearing the CNT_DROP.
And here we get our message printed, clearing the CNT_DROP register field.
So it looks like our callback is working correctly.
Every time the environment detects a write to this CLR register field, it also clears our mirrored value from the CNT_DROP register field.
That's it for this tutorial.
We managed to implement correctly our callback to the CLR register field.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
