# Logic which will model our intermediate buffer

*Chapter: Modeling and checking · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to code together the logic which will model our intermediate buffer.
The first thing that we will have to do is to declare that simple interface and then add in our environment config the virtual interface.
And after that we will add in our model component all the API that we discussed in the previous tutorial.
The starting point is the EDA Playground project called "Model Intermediate Buffer - Practice" which we need to copy.
And now let's resize the windows.
Let's create that interface file.
And let's declare that simple interface.
And now let's include the file in our Aligner package.
And remember, because this is an interface, we have to include the file outside the package declaration.
That's it.
Now let's create a types file for our Aligner package and in the types file we will create the type for the virtual interface.
That's it.
Now let's also include this file in our Aligner package.
That's it.
Now let's go to our testbench and create an instance of this new interface.
That's the instance and now let's put this interface in the database, just like we did for the other interfaces.
Now let's go to our environment config class and in here let's declare the virtual interface.
And now let's declare the getter and the setter for our virtual interface.
That's it.
Now let's add in the start_of_simulation_phase() a simple check to make sure that our virtual interface is configured at that point.
That's it.
And now the only remaining thing is to go to the environment and in the connect_phase() we have to get from the database the virtual interface.
And that's it.
We managed to configure the virtual interface in our environment configuration class.
Now that we have added the virtual interface in our environment config class, let's add the new API in our model component.
And the first thing that we will add is the model of our intermediate buffer and also let's not forget to make the rx_fifo a protected field.
So let's do this.
That's it.
Now let's go to our handle_reset() function and clear this buffer during reset.
And that's it.
Now let's implement this set_rx_fifo_empty() function and this one will be quite similar to this set_rx_fifo_full().
So, let's take the code from the function set_rx_fifo_full() and create our set_rx_fifo_empty() function.
And that's it.
Now let's implement this dec_rx_lvl() function and again this one will be quite similar to inc_rx_lvl().
So, we have here our inc_rx_lvl() function and let's copy this function and create our dec_rx_lvl() function.
That's it.
So, we have this predict() on the RX_LVL register field in which we decrement its value and then if the RX_LVL is equal to 0 then we set our RX_FIFO_EMPTY flag.
Next, let's implement our pop_from_rx_fifo() task.
And just like before, this one will be similar to push_to_rx_fifo() task so we can copy this task but make sure that you don't inject any copy paste error.
That's it.
So, we are getting the data from the rx_fifo, then we are decrementing the RX_LVL, and finally we have this message to show us on the log that the pop happened.
And just be careful that you will have to delete this line that we had in the push_to_rx_fifo() as in the pop case we don't need to inform the scoreboard to expect some response on the RX interface.
Next, let's implement this build_buffer() task.
That's it.
So I declared here the forever loop and in the forever loop I'm comparing the number of bytes inside the buffer with the SIZE field from the Control register.
And to get the number of bytes I'm doing a "sum ... with" syntax so I'm summing all the data.size() from all the items.
If the pop condition is true, then I'm calling this pop_from_rx_fifo() task and then I'm pushing the result in the buffer.
If the pop condition is not true, then I'm simply waiting for the next positive edge of the clock.
Next, let's declare this process_build_buffer pointer.
That's the declaration and now let's go to our handle_reset() function and make sure that we kill this process during reset.
And that's it.
Now the last thing that we have to implement is this build_buffer_nb() function and for this we can go all the way close to the end of the file and our function will be quite similar to this push_to_rx_fifo_nb() so we can copy the code and adapt it.
That's it.
And now the only remaining thing is to start our build_buffer() task, and we can do this by calling this build_buffer_nb() as the last line in our handle_reset() function.
So here.
And that's all the code that we had to implement in order to model our intermediate buffer.
And now let's give it a try and if everything works correctly then we should see in our log the message printed from our pop_from_rx_fifo() function.
So we should see this message printed.
Remember now that in the test we added a legal access of size 4 so this access should go from the rx_fifo to our intermediate buffer.
So let's save and try to run.
The simulation finished and now let's look through our log for that message.
And here is our message.
Our RX_FIFO became empty because we popped from the RX_FIFO that 4 bytes of information.
So these here.
And these ones are matching with the push information from earlier here.
That's it for this tutorial.
We managed to implement correctly in our model the intermediate buffer.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
