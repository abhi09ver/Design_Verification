# How we are going to implement the TX item scoreboard check

*Chapter: Modeling and checking · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about how we are going to implement the TX item scoreboard check.
This is the current API that we implemented so far in our scoreboard class and in order to implement the TX item check, we need some ports in our scoreboard.
We already added these ports in the scoreboard and relevant for us for this TX item scoreboard check are these ones: port_in_model_tx, through which we are getting from the model the expected information and port_in_agent_tx, through which we are getting in the scoreboard the received information from the RTL.
Of course, because these are UVM analysis implementation ports, each of these ports has an associated write() function.
If you remember from the "Scoreboard Architecture" tutorial, we said that for each of the three checks that we need to implement, we need a queue inside our scoreboard to store the expected information.
And just like we did for the RX responses, we will add a queue called exp_tx_items.
In this queue, we will store this type of information: cfs_md_item_mon.
This is the type of information sent by the model to the scoreboard.
In the "Scoreboard Architecture" tutorial, we also talked about the need to start a timer for each entry in this queue.
We can implement these timers as a task which we start every time we push in this queue.
And just like for the RX responses, we can implement a task called exp_tx_item_watchdog().
To manage the processes associated with each instance of this task, we will have to declare a queue called process_exp_tx_item_watchdog in which we will push every time we start that task the pointer to its process.
And finally, the last thing that we need to add in our scoreboard class is a function which will allow us to easily start this watchdog task and push in this queue the pointer to its process and we can call this function exp_tx_item_watchdog_nb().
Once we have all these elements implemented in the scoreboard, then we can easily implement the write() functions associated with the analysis imlementation ports.
In write_in_model_tx(), we will push the expected information coming from the model in this exp_tx_items queue and we will also start this watchdog task.
And in write_in_agent_tx() we will do two things.
First, we will compare the received information from the RTL with the first element from our exp_tx_items queue.
And secondly, we will kill the first process from our process pointers queue.
The last thing that we will have to add is in the environment configuration class, we need to add a threshold field in order to control how many clock cycles our watchdog task will wait until it will trigger an error.
And just like for the RX response, we will initialize this threshold with value 10.
That's it for this tutorial.
We talked about the new API that we need to add in order to implement the TX item check.
In the next tutorial, we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
