using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class RightTentacleMovement : MonoBehaviour
{
    public GameObject Tentacle;

    public int moveSpeed = 25;
    public int force = 25;
    
    // Start is called before the first frame update
    void Start()
    {
    }

    // Update is called once per frame
    void Update()
    {
        if (Input.GetKeyDown(KeyCode.D))
        {
           Tentacle.transform.position = Tentacle.transform.position + new Vector3(force,0,0);
        }
        else{
            Tentacle.transform.position += Vector3.left * moveSpeed * Time.deltaTime;
        }
        
    }
}
