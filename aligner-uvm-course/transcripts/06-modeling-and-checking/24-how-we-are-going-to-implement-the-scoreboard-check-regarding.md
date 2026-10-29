# How we are going to implement the scoreboard check regarding the RX response

*Chapter: Modeling and checking · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about how we are going to implement the scoreboard check regarding the RX response.
This is the current API that we implemented in our scoreboard and let's see what else we need to add in order to implement this check for the RX response.
Remember that in the previous tutorial we added several ports in our scoreboard.
Through these ports we are receiving the expected information from our model and also the DUT output information collected by the agents.
In the case of the RX response check relevant for us are two ports: port_in_model_rx through which we are receiving the expected RX response from the model, and port_in_agent_rx through which we are receiving the full RX transaction collected by our agent.
And because these are UVM analysis implementation ports, they both have associated write() functions.
So these are already declared in our scoreboard and we can make use of it.
Now let's see exactly what else we need to add.
When we discussed the scoreboard architecture, we said that we need in the scoreboard a queue in which to store the expected information.
And in the case of the RX response, we need to add in the scoreboard a queue called exp_rx_responses.
In that scoreboard architecture tutorial we also said that for each entry in this queue we need to start some sort of a timer or a counter and the job of this counter is to count the number of clock cycles a particular entry stays in this queue.
In this way we can easily implement a check which will catch the scenario in which the DUT is stuck and never outputs anything.
And the logic is quite simple, if this counter goes past a certain threshold then we simply trigger an error.
We can implement this simple algorithm in a task called exp_rx_response_watchdog().
And we can start this task for every entry pushed in this queue.
Of course we want to control all these processes that we will start in parallel and for this we will declare a queue of process pointers and we will call this process_exp_rx_response_watchdog.
The main thing that we want to do with these processes is kill them during reset and for this we can create a function to which we will pass a reference to this queue and then the function will kill all the processes inside and we can call this function kill_processes_from_queue().
Just like before, when we have a task and its associated process, or in this case processes, we want to allocate that process and start the task in a non-blocking function.
So, for this, we will declare a function called exp_rx_reponse_watchdog_nb() in which we will do exactly this.
We will start this task and then push the pointer to its process in this queue.
Once we have all this, we can implement the main logic of this check and this means that we can implement these two functions: write_in_model_rx(), in which we will push this expected response in this queue and start this watchdog task.
And then in write_in_agent_rx() we will compare the information coming from the monitor, so from the RTL, with the first entry in this exp_rx_responses.
The last thing that we have to add is a configuration field in our environment configuration class.
This field will determine how many clock cycles this watchdog task will have to wait until it will trigger an error.
We can call this field exp_rx_response_threshold which we can initialize to let's say value 10 in the constructor of the class and for this we must also declare a gettter and a setter.
That's it for this tutorial.
We talked about what API we need to add in order to implement the check for the RX response.
In the next tutorial we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
