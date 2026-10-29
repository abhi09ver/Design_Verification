# Scoreboard interface

*Chapter: Modeling and checking · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to code together the scoreboard interface.
This means that we will declare the scoreboard class and inside we will declare all these UVM analysis implementation ports.
The starting point is the EDA Playground project called "Scoreboard Interface - Practice" which we need to copy.
And now let's resize the windows.
The first thing that we have to do is to create the scoreboard file.
And now let's include this file in our Aligner package.
That's it.
And now let's go back to our file and declare the scoreboard class.
That's it.
And now let's declare an empty function called handle_reset() which is part of this reset handler.
And that's it.
Now we can instantiate this scoreboard class in our environment class.
So let's declare the handler here.
So that's the handler.
And now in build_phase(), let's create an instance of our scoreboard.
And that's it.
Now let's go to our scoreboard and declare the analysis implementation classes and for this we can use that macro `uvm_analysis_imp_decl().
So let's do this.
That's it and now let's declare the port handlers in our scoreboard class.
So that's the handler for the port through which we will receive the expected RX response from the model.
And now let's declare the port for the expected TX information.
That's it.
So if you are doing a copy/paste from above, pay attention that you have to update the type here, here and the name to be TX.
Let's do the same thing for the expected interrupt request information.
And now for the incoming information from the agents.
And that's it.
Now let's create instances of these analysis implementation ports in our constructor.
That's it.
And finally let's declare the write() functions associated with these ports.
And that's it.
Here you must pay attention to the type of information declared for each of these write() functions.
The last thing that we have to declare in the scoreboard is the pointer to the environment configuration class.
So let's declare it here.
And that's it.
And now the last thing that we have to do is to connect all these ports and pointer and we can do this in our environment class in the connect_phase().
So here.
That's it.
So we connected the pointer to the environment config class and then the five ports.
Three from the model and two from the agents.
That's it for this tutorial.
We managed to implement successfully the scoreboard interface.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
